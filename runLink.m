function results = runLink(params)
%RUNLINK Simulate one 5G NR PDSCH link with CQI-based AMC at one SNR point.
%   results = runLink(params) runs the link for params.NFrames frames at
%   params.SNRdB and returns throughput, BLER, spectral efficiency, the
%   share of each modulation used, and the reported CQI values.
%
%   params comes from baseConfig() (possibly changed by an evaluation).
%
%   Adapted from the MathWorks 5G Toolbox example "NR PDSCH Throughput
%   Using Channel State Information Feedback" (R2026b). Changes:
%     - turned into a function: all settings come from the params struct
%     - TDL channel, SISO / rank-1, 30 kHz SCS, 51 RB by default
%     - CSI-RS period set equal to the CSI report period
%     - max Doppler computed from UE speed and carrier frequency
%     - optional fixed MCS (CQI no longer changes modulation/code rate)
%     - counts BLER, throughput over the counted slots only, spectral
%       efficiency, and logs the modulation used in each slot
%     - removed slot printing and EVM plots
%
%   Requires the helper files shipped with the example (hCSIDecode.m,
%   hCSIEncode.m, hSkipWeakTimingOffset.m, ...) on the MATLAB path.

    simParameters = buildSimParameters(params);
    rng(params.Seed,"twister");

    % Set up transmitter, channel and receiver
    csiFeedbackOpts = getCSIFeedbackOptions(simParameters);
    [carrier,encodeDLSCH,pdsch,pdschextra,csirs,wtx] = setupTransmitter(simParameters);
    [channel,maxChDelay] = setupChannel(simParameters);
    [decodeDLSCH,timingOffset,N0,noiseEst,csiReports,csiSlots] = ...
        setupReceiver(simParameters,channel,csiFeedbackOpts);
    csirsCDMLengths = getCSIRSCDMLengths(csirs);

    NSlots = simParameters.NFrames * carrier.SlotsPerFrame;
    slotDuration = 1e-3 / carrier.SlotsPerSubframe;   % s

    useFixedMCS = ~isempty(params.FixedMCS);

    % As in the example: with practical channel estimation in RI-PMI-CQI
    % mode, only count slots after the first in-loop CSI report is applied
    countFromStart = simParameters.PerfectChannelEstimator || ...
        simParameters.CSIReportMode ~= "RI-PMI-CQI";
    inLoopCSIApplied = false;

    % Counters
    bitsOK = 0;          % correctly received bits
    bitsTx = 0;          % transmitted bits
    nBlocks = 0;         % transport blocks
    nBlockErr = 0;       % failed transport blocks
    nCounted = 0;        % counted slots
    QmLog = zeros(NSlots,1);   % bits per symbol used in each counted slot

    for nslot = 0:NSlots-1

        carrier.NSlot = nslot;

        % Apply a new CSI report if one is available in this slot
        [isNewReport,repIdx] = ismember(nslot,csiSlots);
        if isNewReport
            [newMod,newTCR,wtx] = hCSIDecode(carrier,pdsch,pdschextra, ...
                csiReports(repIdx),csiFeedbackOpts);
            pdsch.NumLayers = size(wtx,1);
            if useFixedMCS
                % Keep precoder/layers from CSI, but ignore the CQI
                pdsch.Modulation = params.FixedMCS.Modulation;
                pdschextra.TargetCodeRate = params.FixedMCS.TargetCodeRate;
            else
                pdsch.Modulation = newMod;
                pdschextra.TargetCodeRate = newTCR;
            end
            encodeDLSCH.TargetCodeRate = pdschextra.TargetCodeRate;
            if nslot > 0
                inLoopCSIApplied = true;
            end
        end

        % Resource grid and CSI-RS mapping
        dlGrid = nrResourceGrid(carrier,csirs.NumCSIRSPorts(1));
        csirsInd = nrCSIRSIndices(carrier,csirs);
        csirsSym = nrCSIRS(carrier,csirs);
        dlGrid(csirsInd) = csirsSym;
        csirsTransmission = ~isempty(csirsInd);
        pdsch.ReservedRE = csirsInd-1;   % 0-based

        % Transport block sizes and new data
        [pdschIndices,pdschIndicesInfo] = nrPDSCHIndices(carrier,pdsch);
        trBlkSizes = nrTBS(pdsch.Modulation,pdsch.NumLayers,numel(pdsch.PRBSet), ...
            pdschIndicesInfo.NREPerPRB,pdschextra.TargetCodeRate,pdschextra.XOverhead);
        for cwIdx = 1:pdsch.NumCodewords
            trBlk = randi([0 1],trBlkSizes(cwIdx),1);
            setTransportBlock(encodeDLSCH,trBlk,cwIdx-1);
            resetSoftBuffer(decodeDLSCH,cwIdx-1);   % no HARQ
        end

        % DL-SCH encoding (RV = 0, no retransmissions)
        RV = zeros(1,pdsch.NumCodewords);
        codedTrBlocks = encodeDLSCH(pdsch.Modulation,pdsch.NumLayers,pdschIndicesInfo.G,RV);

        % PDSCH modulation, precoding and DM-RS
        pdschSymbols = nrPDSCH(carrier,pdsch,codedTrBlocks);
        [pdschAntSymbols,pdschAntIndices] = nrPDSCHPrecode(carrier,pdschSymbols,pdschIndices,wtx);
        dlGrid(pdschAntIndices) = pdschAntSymbols;
        dmrsSymbols = nrPDSCHDMRS(carrier,pdsch);
        dmrsIndices = nrPDSCHDMRSIndices(carrier,pdsch);
        [dmrsAntSymbols,dmrsAntIndices] = nrPDSCHPrecode(carrier,dmrsSymbols,dmrsIndices,wtx);
        dlGrid(dmrsAntIndices) = dmrsAntSymbols;

        % OFDM modulation, channel and noise
        txWaveform = nrOFDMModulate(carrier,dlGrid);
        txWaveform = [txWaveform; zeros(maxChDelay,size(txWaveform,2))]; %#ok<AGROW>
        [rxWaveform,ofdmResponse,tOffset] = channel(txWaveform,carrier);
        noise = N0*randn(size(rxWaveform),"like",1i);
        rxWaveform = rxWaveform + noise;

        % Synchronization
        if simParameters.PerfectChannelEstimator
            timingOffset = tOffset;
        else
            [t,mag] = nrTimingEstimate(carrier,rxWaveform,dmrsIndices,dmrsSymbols);
            timingOffset = hSkipWeakTimingOffset(timingOffset,t,mag);
        end
        rxWaveform = rxWaveform(1+timingOffset:end,:);

        % OFDM demodulation (pad if an incomplete slot was demodulated)
        rxGrid = nrOFDMDemodulate(carrier,rxWaveform);
        [K,L,R] = size(rxGrid);
        if L < carrier.SymbolsPerSlot
            rxGrid = cat(2,rxGrid,zeros(K,carrier.SymbolsPerSlot-L,R));
        end

        % Channel estimation for PDSCH
        if simParameters.PerfectChannelEstimator
            Hest = ofdmResponse;
            [pdschRx,pdschHest,~,pdschHestIndices] = nrExtractResources(pdschIndices,rxGrid,Hest);
            pdschHest = nrPDSCHPrecode(carrier,pdschHest,pdschHestIndices,permute(wtx,[2 1 3]));
        else
            aw = channelEstimateAveragingWindow(pdsch);
            [Hest,noiseEst] = nrChannelEstimate(carrier,rxGrid,dmrsIndices,dmrsSymbols, ...
                PRGBundleSize=pdschextra.PRGBundleSize,CDMLengths=pdsch.DMRS.CDMLengths,AveragingWindow=aw);
            noiseEst = mean(noiseEst,'all');
            [pdschRx,pdschHest] = nrExtractResources(pdschIndices,rxGrid,Hest);
        end

        % Equalization and PDSCH decoding
        [pdschEq,eqCSIScaling] = nrEqualizeMMSE(pdschRx,pdschHest,noiseEst);
        [dlschLLRs,rxSymbols] = nrPDSCHDecode(carrier,pdsch,pdschEq,noiseEst);

        % Scale LLRs by equalizer CSI
        eqCSIScaling = nrLayerDemap(eqCSIScaling);
        for cwIdx = 1:pdsch.NumCodewords
            Qm = length(dlschLLRs{cwIdx})/length(rxSymbols{cwIdx});
            eqCSIScaling{cwIdx} = repmat(eqCSIScaling{cwIdx}.',Qm,1);
            dlschLLRs{cwIdx} = dlschLLRs{cwIdx} .* eqCSIScaling{cwIdx}(:);
        end

        % DL-SCH decoding
        decodeDLSCH.TransportBlockLength = trBlkSizes;
        decodeDLSCH.TargetCodeRate = pdschextra.TargetCodeRate;
        [~,blkerr] = decodeDLSCH(dlschLLRs,pdsch.Modulation,pdsch.NumLayers,RV);

        % Count results
        if countFromStart || inLoopCSIApplied
            bitsOK    = bitsOK + sum(~blkerr .* trBlkSizes);
            bitsTx    = bitsTx + sum(trBlkSizes);
            nBlocks   = nBlocks + numel(blkerr);
            nBlockErr = nBlockErr + sum(blkerr);
            nCounted  = nCounted + 1;
            QmLog(nCounted) = bitsPerSymbol(pdsch.Modulation);
        end

        % CSI measurement and report (fed back with delay)
        if csirsTransmission
            if ~simParameters.PerfectChannelEstimator
                nzpind = (csirsSym ~= 0);
                [Hest,noiseEst] = nrChannelEstimate(carrier,rxGrid, ...
                    csirsInd(nzpind),csirsSym(nzpind),'CDMLengths',csirsCDMLengths);
            end
            csiReport = hCSIEncode(carrier,csirs,Hest,noiseEst,csiFeedbackOpts);
            feedbackSlot = nextCSISlot(csiFeedbackOpts.CSIReportPeriod, ...
                1+nslot+simParameters.UEProcessingDelay);
            csiSlots(end+1) = 1+feedbackSlot+simParameters.BSProcessingDelay; %#ok<AGROW>
            csiReports(end+1) = csiReport; %#ok<AGROW>
            csiReports = reduceCSIReports(csiReports,csiSlots,carrier.NSlot, ...
                simParameters.CSIReportMode);
        end
    end

    % Results
    simTime = max(nCounted,1) * slotDuration;          % s
    results = struct();
    results.params             = params;
    results.SNRdB              = params.SNRdB;
    results.MaxDopplerHz       = simParameters.MaximumDopplerShift;
    results.CountedSlots       = nCounted;
    results.ThroughputMbps     = bitsOK / simTime / 1e6;
    results.MaxThroughputMbps  = bitsTx / simTime / 1e6;
    results.BLER               = nBlockErr / max(nBlocks,1);
    results.SpectralEfficiency = (bitsOK / simTime) / params.ChannelBandwidthHz;  % bit/s/Hz
    QmLog = QmLog(1:nCounted);
    results.ModulationOrders   = [2 4 6 8];                                 % QPSK..256QAM
    results.ModulationShare    = arrayfun(@(q) mean(QmLog==q), [2 4 6 8]);
    try
        results.CQI = arrayfun(@(r) r.CQI(1), csiReports);
    catch
        results.CQI = [];
    end
end

%% ------------------------------------------------------------------------
%  Configuration (replaces the hard-coded simParameters block of the example)
%  ------------------------------------------------------------------------
function s = buildSimParameters(p)

    s = struct();
    s.NFrames = p.NFrames;
    s.SNRdB = p.SNRdB;
    s.PerfectChannelEstimator = p.PerfectChannelEstimator;

    % Carrier
    s.Carrier = nrCarrierConfig;
    s.Carrier.NSizeGrid = p.NSizeGrid;
    s.Carrier.SubcarrierSpacing = p.SubcarrierSpacing;
    s.Carrier.CyclicPrefix = 'Normal';
    s.Carrier.NCellID = 1;

    % PDSCH: full band, slot-wise, first 2 OFDM symbols reserved
    s.PDSCH = nrPDSCHConfig;
    s.PDSCH.MappingType = "A";
    s.PDSCH.SymbolAllocation = [2 s.Carrier.SymbolsPerSlot-2];
    s.PDSCH.PRBSet = 0:s.Carrier.NSizeGrid-1;
    s.PDSCH.NID = s.Carrier.NCellID;
    s.PDSCH.RNTI = 1;

    % DM-RS (example defaults)
    s.PDSCH.DMRS.DMRSTypeAPosition       = 2;
    s.PDSCH.DMRS.DMRSLength              = 2;
    s.PDSCH.DMRS.DMRSAdditionalPosition  = 1;
    s.PDSCH.DMRS.DMRSConfigurationType   = 2;
    s.PDSCH.DMRS.NumCDMGroupsWithoutData = 3;

    % DL-SCH / PDSCH extras
    s.PDSCHExtension = struct();
    s.PDSCHExtension.PRGBundleSize = 4;
    s.PDSCHExtension.MCSTable = p.MCSTable;
    s.PDSCHExtension.XOverhead = [];
    s.PDSCHExtension.LDPCDecodingAlgorithm = p.LDPCDecodingAlgorithm;
    s.PDSCHExtension.MaximumLDPCIterationCount = p.MaximumLDPCIterationCount;

    % Antenna panels
    s.TransmitAntennaArray.NumPanels        = 1;
    s.TransmitAntennaArray.PanelDimensions  = p.TxPanelDimensions;
    s.TransmitAntennaArray.NumPolarizations = p.TxPolarizations;
    s.ReceiveAntennaArray.NumPanels         = 1;
    s.ReceiveAntennaArray.PanelDimensions   = p.RxPanelDimensions;
    s.ReceiveAntennaArray.NumPolarizations  = p.RxPolarizations;
    s.TransmitAntennaArray = validateAntennaPolarization(s.TransmitAntennaArray);
    s.NTxAnts = numAntennaElements(s.TransmitAntennaArray);
    s.NRxAnts = numAntennaElements(s.ReceiveAntennaArray);

    % CSI-RS (period equal to the CSI report period)
    s.CSIRS = nrCSIRSConfig;
    s.CSIRS.CSIRSPeriod = [p.CSIReportPeriod 0];
    s.CSIRS.Density = "one";
    s.CSIRS.NumRB = s.Carrier.NSizeGrid;
    [rowNumber,subcarriers,symbols,density] = csirsAllocationParameters(s);
    s.CSIRS.RowNumber = rowNumber;
    s.CSIRS.SubcarrierLocations = subcarriers;
    s.CSIRS.SymbolLocations = symbols;
    s.CSIRS.Density = density;
    validateCSIRSConfig(s.Carrier,s.CSIRS,s.NTxAnts);

    % CSI feedback
    s.CSIReportMode = 'RI-PMI-CQI';
    s.CSIReportPeriod = [p.CSIReportPeriod 0];
    s.CSIReportConfig = nrCSIReportConfig;
    s.CSIReportConfig.CQITable = p.CQITable;
    s.CSIReportConfig.CQIFormatIndicator = 'Wideband';
    s.CSIReportConfig.PMIFormatIndicator = 'Wideband';
    s.CSIReportConfig.CodebookType = 'Type1SinglePanel';
    s.CSIReportConfig.SubbandSize = 4;
    s.CSIReportConfig.CodebookMode = 1;
    s.CSIReportConfig.RIRestriction = p.RIRestriction;
    s.CSIReportConfig.NStartBWP = [];
    s.CSIReportConfig.NSizeBWP = [];
    s.CSIReportConfig = updateCSIReportPanelInfo(s.CSIReportConfig,s.TransmitAntennaArray);
    s.CSIReportConfig.RIRestriction = updateRankRestriction(s.PDSCH.DMRS,s.CSIReportConfig);
    s.UEProcessingDelay = p.UEProcessingDelay;
    s.BSProcessingDelay = p.BSProcessingDelay;

    % Propagation channel: Doppler from UE speed, f_D = v * fc / c
    s.DelayProfile = p.DelayProfile;
    s.DelaySpread = p.DelaySpread;
    s.MaximumDopplerShift = (p.UESpeedKmh/3.6) * p.CarrierFrequency / 299792458;
    s.Channel = createChannel(s);
end

function qm = bitsPerSymbol(modulation)
% Bits per symbol for a modulation name (first codeword if a cell array)
    if iscell(modulation)
        modulation = modulation{1};
    end
    switch upper(string(modulation))
        case "QPSK",    qm = 2;
        case "16QAM",   qm = 4;
        case "64QAM",   qm = 6;
        case "256QAM",  qm = 8;
        case "1024QAM", qm = 10;
        otherwise,      qm = NaN;
    end
end

%% ------------------------------------------------------------------------
%  Local functions from the MathWorks example (unchanged unless noted)
%  ------------------------------------------------------------------------
function [carrier,eDLSCH,pdsch,pdschextra,csirs,wtx] = setupTransmitter(simParameters)
    carrier = simParameters.Carrier;
    pdsch = simParameters.PDSCH;
    pdschextra = simParameters.PDSCHExtension;
    csirs = simParameters.CSIRS;
    if isempty(pdschextra.XOverhead)
        pdschextra.XOverhead = getXOverhead(carrier,csirs);
    end
    eDLSCH = nrDLSCH;
    wtx = 1;
end

function [decodeDLSCH,timingOffset,N0,noiseEst,csiReports,csiAvailableSlots] = setupReceiver(simParameters,channel,csiFeedbackOpts)
% Changed: takes the SNR from simParameters.SNRdB (one SNR point per call)
    decodeDLSCH = nrDLSCHDecoder;
    decodeDLSCH.LDPCDecodingAlgorithm = simParameters.PDSCHExtension.LDPCDecodingAlgorithm;
    decodeDLSCH.MaximumLDPCIterationCount = simParameters.PDSCHExtension.MaximumLDPCIterationCount;

    carrier = simParameters.Carrier;
    waveInfo = nrOFDMInfo(carrier);
    SNR = 10^(simParameters.SNRdB/10);
    N0 = 1/sqrt(double(waveInfo.Nfft)*SNR);

    chInfo = info(channel);
    if channel.NormalizeChannelOutputs
        if contains(simParameters.DelayProfile,'CDL')
            N0 = N0/sqrt(chInfo.NumOutputSignals);
        else
            N0 = N0/sqrt(chInfo.NumReceiveAntennas);
        end
    end

    [Hest,timingOffset] = getInitialChannelEstimate(carrier,channel,chInfo.MaximumChannelDelay);
    noiseEst = N0^2*double(waveInfo.Nfft);

    csirs = simParameters.CSIRS;
    csiFeedbackOpts.PerfectChannelEstimator = true;
    csirs.CSIRSPeriod = 'on';
    csiReports = hCSIEncode(carrier,csirs,Hest,noiseEst,csiFeedbackOpts);
    csiAvailableSlots = 0;
end

function channel = createChannel(simParameters)
    if contains(simParameters.DelayProfile,'CDL')
        channel = nrCDLChannel;
        txArray = simParameters.TransmitAntennaArray;
        M = txArray.PanelDimensions(2);
        N = txArray.PanelDimensions(1);
        Ng = txArray.NumPanels;
        P = txArray.NumPolarizations;
        channel.TransmitAntennaArray.Size = [M N P 1 Ng];
        channel.TransmitAntennaArray.ElementSpacing = [0.5 0.5 1 N/2];
        channel.TransmitAntennaArray.PolarizationAngles = [-45 45];
        rxArray = simParameters.ReceiveAntennaArray;
        M = rxArray.PanelDimensions(2);
        N = rxArray.PanelDimensions(1);
        Ng = rxArray.NumPanels;
        P = rxArray.NumPolarizations;
        channel.ReceiveAntennaArray.Size = [M N P 1 Ng];
        channel.ReceiveAntennaArray.ElementSpacing = [0.5 0.5 1 N/2];
        channel.ReceiveAntennaArray.PolarizationAngles = [0 90];
    elseif contains(simParameters.DelayProfile,'TDL')
        channel = nrTDLChannel;
        channel.NumTransmitAntennas = simParameters.NTxAnts;
        channel.NumReceiveAntennas = simParameters.NRxAnts;
    else
        error('Channel not supported.')
    end
    channel.DelayProfile = simParameters.DelayProfile;
    channel.DelaySpread = simParameters.DelaySpread;
    channel.MaximumDopplerShift = simParameters.MaximumDopplerShift;
    channel.ChannelResponseOutput = 'ofdm-response';
    waveInfo = nrOFDMInfo(simParameters.Carrier);
    channel.SampleRate = waveInfo.SampleRate;
end

function [channel,maxChannelDelay] = setupChannel(simParameters)
    channel = simParameters.Channel;
    channel.reset();
    chInfo = info(channel);
    maxChannelDelay = chInfo.MaximumChannelDelay;
end

function [ofdmResponse,toffset] = getInitialChannelEstimate(carrier,channel,maxChannelDelay)
    channel = clone(channel);
    release(channel);
    channel.ChannelFiltering = false;
    ofdmInfo = nrOFDMInfo(carrier);
    channel.NumTimeSamples = (ofdmInfo.SampleRate*1e-3/carrier.SlotsPerSubframe) + maxChannelDelay;
    [ofdmResponse,toffset] = channel(carrier);
end

function aw = channelEstimateAveragingWindow(pdsch)
    aw = [0 0];
    if pdsch.DMRS.DMRSLength == 2
        aw = [0 7];
    end
end

function XOverhead = getXOverhead(carrier,csirs)
    [~,csirsInfo] = nrCSIRSIndices(carrier,csirs);
    csirsRE = length(csirsInfo.KBarLBar{1})*length(csirsInfo.KPrime{1})*length(csirsInfo.LPrime{1});
    [~,XOverhead] = quantiz(csirsRE,[0 6 12],[0 6 12 18]);
    if csirsRE > XOverhead
        warning("The CSI-RS RE overhead is higher than the maximum 18. This can result in decoding failures.")
    end
end

function cdmLengths = getCSIRSCDMLengths(csirs)
    CDMType = csirs.CDMType;
    if ~iscell(csirs.CDMType)
        CDMType = {csirs.CDMType};
    end
    CDMTypeOpts = {'noCDM','fd-CDM2','CDM4','CDM8'};
    CDMLengthOpts = {[1 1],[2 1],[2 2],[2 4]};
    cdmLengths = CDMLengthOpts{strcmpi(CDMTypeOpts,CDMType{1})};
end

function csiFeedbackOpts = getCSIFeedbackOptions(simParameters)
    csiFeedbackOpts = struct();
    csiFeedbackOpts.CSIReportMode = simParameters.CSIReportMode;
    csiFeedbackOpts.CSIReportPeriod = simParameters.CSIReportPeriod;
    csiFeedbackOpts.CSIReportConfig = simParameters.CSIReportConfig;
    csiFeedbackOpts.PerfectChannelEstimator = simParameters.PerfectChannelEstimator;
    csiFeedbackOpts.DMRSConfig = simParameters.PDSCH.DMRS;
end

function csiReportConfig = updateCSIReportPanelInfo(csiReportConfig,antennaArray)
    if antennaArray.NumPanels > 1 && csiReportConfig.CodebookType ~= "Type1MultiPanel"
        csiReportConfig.CodebookType = "Type1MultiPanel";
        warning("For transmit antenna arrays with more than one panel, the codebook type must be 'Type1MultiPanel'. The codebook type is set to 'Type1MultiPanel'.");
    end
    if strcmpi(csiReportConfig.CodebookType,'Type1MultiPanel')
        csiReportConfig.PanelDimensions = [antennaArray.NumPanels antennaArray.PanelDimensions];
    else
        csiReportConfig.PanelDimensions = [1 antennaArray.PanelDimensions];
    end
end

function csislot = nextCSISlot(period,nslot)
    p = period(1);
    o = period(2);
    csislot = p*ceil((nslot-o)/p)+o;
end

function csiReports = reduceCSIReports(csiReports,csiAvailableSlots,nslot,csiMode)
    prevSlots = csiAvailableSlots < nslot;
    if csiMode == "RI-PMI-CQI"
        [csiReports(prevSlots).W] = deal([]);
    else
        [csiReports(prevSlots).H] = deal([]);
    end
end

function txArray = validateAntennaPolarization(txArray)
    numTxElements = numAntennaElements(txArray);
    if numTxElements > 1 && txArray.NumPolarizations == 1
        txArray.NumPolarizations = 2;
        warning("For transmit antenna arrays with more than one element, the number of polarizations must be 2. The number of polarizations is set to 2.")
    end
end

function numElements = numAntennaElements(antArray)
    numElements = antArray.NumPolarizations*antArray.NumPanels*prod(antArray.PanelDimensions);
end

function ranks = updateRankRestriction(dmrsConfig,CSIReportConfig)
    ranks = CSIReportConfig.RIRestriction;
    if ~dmrsConfig.DMRSEnhancedR18 && (dmrsConfig.DMRSLength == 1) && strcmpi(CSIReportConfig.CodebookType,'Type1SinglePanel')
        if (dmrsConfig.DMRSConfigurationType == 1)
            dmrsRankRestriction = [ones(1,4) zeros(1,4)];
        else
            dmrsRankRestriction = [ones(1,6) zeros(1,2)];
        end
        if isempty(ranks)
            ranks = ones(1,8);
        end
        ranks = ranks.*dmrsRankRestriction;
    end
end

function validateCSIRSConfig(carrier,csirs,nTxAnts)
    if ~isscalar(unique(csirs.NumCSIRSPorts))
        error('nr5g:InvalidCSIRSPorts', ...
            'All the CSI-RS resources must be configured to have the same number of CSI-RS ports.');
    end
    if any(csirs.Ports_Options(csirs.RowNumber) ~= nTxAnts)
        rn = num2str(find(csirs.Ports_Options == nTxAnts),'%3d,');
        error('The number of CSI-RS ports must be equal to the number of Tx antenna elements. Valid CSI-RS row numbers are (%s).',rn(1:end-1))
    end
    if nTxAnts ~= csirs.NumCSIRSPorts(1)
        error('nr5g:InvalidNumTxAnts',['Number of transmit antennas (' num2str(nTxAnts) ...
            ') must be equal to the number of CSI-RS ports (' num2str(csirs.NumCSIRSPorts(1)) ').']);
    end
    % (overlap checks of the original example omitted: one CSI-RS resource)
    nrCSIRSIndices(carrier,csirs); %#ok<VUNUS> % errors if the configuration is invalid
end

function [rowNumber,subcarriers,symbols,density] = csirsAllocationParameters(simParameters)
    carrier = simParameters.Carrier;
    pdsch = simParameters.PDSCH;
    numPorts   = [1 2 4 8 12 16 24 32];
    rowNumbers = [2 3 4 6  9 11 13 16];
    userNumPorts = numAntennaElements(simParameters.TransmitAntennaArray);
    rowNumber = rowNumbers(userNumPorts==numPorts);
    kiLengths = [1 1 1 1 1 4 2 2 6 3 4 4 3 3 3 4 4 4];
    numSubcarriers = kiLengths(rowNumber);
    scStep = 12./numSubcarriers;
    subcarriers = 0:scStep:11; %#ok<BDSCI>
    dmrsind = nrPDSCHDMRSIndices(carrier,pdsch,"IndexStyle","subscript");
    dmrssym = unique(dmrsind(:,2))-1;
    slotSymbolSet = 2:carrier.SymbolsPerSlot-2;
    slotSymbolSet = setdiff(slotSymbolSet,dmrssym);
    nsyms = [1 1 1 1 1 1 1 1 1 1 1 1 2 2 1 2 2 1];
    nsym = nsyms(rowNumber);
    symbols = slotSymbolSet(1:2:2*nsym);
    density = simParameters.CSIRS.Density;
    if (density ~= "one") && any(rowNumber == (4:10))
        density = "one";
    end
end
