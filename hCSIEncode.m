function csiReport = hCSIEncode(carrier,csirs,H,nVar,alg)
%hCSIEncode Encode channel state information (CSI)
%   CSIREPORT = hCSIEncode(CARRIER,CSIRS,H,NVAR,ALG) returns the channel
%   state information report CSIREPORT corresponding to the channel
%   estimates H, noise estimate NVAR, and the selected algorithmic
%   configuration ALG.
%
%   CARRIER is a carrier configuration object, as described in <a href="matlab:help('nrCarrierConfig')">nrCarrierConfig</a>.
%
%   CSIRS is a CSI-RS configuration object, as described in <a href="matlab:help('nrCSIRSConfig')">nrCSIRSConfig</a>.
%
%   H is the channel estimation matrix of size K-by-L-by-nRxAnts-by-P,
%   where K is the number of subcarriers in the carrier resource grid, L is
%   the number of OFDM symbols spanning one slot, nRxAnts is the number of
%   receive antennas, and P is the number of CSI-RS antenna ports.
%
%   NVAR is the estimated noise variance at the receiver specified as a
%   nonnegative scalar.
%
%   ALG is an algorithmic configuration structure with these fields:
%   CSIReportMode   - 'RI-PMI-CQI','Perfect CSI','CSINet','CLNet - PyTorch'.
%                     For more information about these modes, see the
%                     description of the CSIREPORT output.
%   These fields only apply when CSIReportMode = 'RI-PMI-CQI':
%   CSIReportConfig - CSI report configuration object, as described in <a href="matlab:help('nrCSIReportConfig')">nrCSIReportConfig</a>
%   PerfectChannelEstimator - (Optional) true or false. Default true.
%   DMRSConfig      - Demodulation reference signal (DM-RS) configuration
%                     object for the physical downlink shared channel
%                     (PDSCH), as described in <a href="matlab:help('nrPDSCHDMRSConfig')">nrPDSCHDMRSConfig</a>.
%   Only these object properties are relevant for this function:
%   DMRSLength              - DM-RS length (1 (default), 2)
%   DMRSAdditionalPosition  - Maximum number of DM-RS additional positions
%                             (0...3) (default 0)
%   DMRSEnhancedR18         - Enable enhanced DM-RS multiplexing
%                             (0 (default), 1)
%   These fields only apply when CSIReportMode is an AI model
%   CSIEncoder              - Encoder neural network
%   AutoEncOptions          - Structure with neural network related options
%
%   CSIREPORT is a structure containing the CSI report.
%   When ALG.CSIReportMode = 'RI-PMI-CQI', CSIREPORT contains these fields:
%   RI      - Rank indicator
%   PMI     - Precoding matrix indicator
%   CQI     - Channel quality indicator
%   W       - Precoding matrix associated with the reported PMI.
%   NSlot   - Number of the slot in which the report was generated.
%   For more information about RI, PMI, and CQI, see the outputs of <a href="matlab:help('nrCSIReportCSIRS')">nrCSIReportCSIRS</a>.
%   When ALG.CSIReportMode = 'Perfect CSI', CSIREPORT contains these fields:
%   H       - Input channel estimate matrix H.
%   NVAR    - Noise variance estimate.
%   NSlot   - Number of the slot in which the report was generated.
%
%   See also hCSIDecode

%   Copyright 2022-2026 The MathWorks, Inc.

switch(alg.CSIReportMode)
    case "RI-PMI-CQI"
        % In 5G, the CSI report includes the rank indicator (RI), precoding
        % matrix indicator (PMI), and channel quality indicator (CQI).
        [rank,cqi,pmi,W] = hCSISelect(carrier,csirs,alg.DMRSConfig,alg.CSIReportConfig,H,nVar,alg);
        % Create CSI report
        csiReport = csiReportStruct(carrier.NSlot,rank,cqi,pmi,W);

    case "Perfect CSI"
        Hc = H;
        % Create CSI report
        csiReport = csiReportStruct(carrier.NSlot,Hc,nVar);

    otherwise       % This section is used in Test AI-based CSI Compression Techniques for Enhanced PDSCH Throughput Example
        % Compress channel estimates using an AI network
        Hc = hCSICompress(alg.CSIEncoder,H,alg.AutoEncOptions);
        % Create CSI report
        csiReport = csiReportStruct(carrier.NSlot,Hc,nVar);
end


end

function csiReport = csiReportStruct(nSlot,varargin)
%CSIREPORTSTRUCT Pack CSI feedback into a struct

csiReport = struct();
csiReport.NSlot = nSlot;

if nargin == 3
    % AI-Based/Perfect Feedback Case: (NSlot, H, nVar)
    csiReport.H = varargin{1};
    csiReport.nVar = varargin{2};
else
    % Standard Codebook Feedback Case: (NSlot, RI, CQI, PMI, W)
    csiReport.RI = varargin{1};
    csiReport.CQI = varargin{2};
    csiReport.PMI = varargin{3};
    csiReport.W = varargin{4};
end
end

function [rank,cqi,pmi,w] = hCSISelect(carrier,csirs,dmrsConfig,reportConfig,H,nVar,alg)
% Select RI, PMI, and CQI for the input channel and noise estimates

    if isfield(alg,'PerfectChannelEstimator') && ~alg.PerfectChannelEstimator
        nVar = nVar*1.602;
    end
    
    % Calculate the RI, PMI and CQI values using channel estimate
    [csiReport,csiReportInfo] = nrCSIReportCSIRS(carrier,csirs,reportConfig,dmrsConfig,H,nVar);

    % Collect CSI
    rank = csiReport.RI;
    cqi = csiReport.CQI;
    pmi = csiReport.PMISet;
    w = csiReportInfo.PrecodingMatrix;
end