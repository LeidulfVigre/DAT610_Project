function p = baseConfig()
%BASECONFIG Fixed scenario parameters shared by all evaluations.
%   p = baseConfig() returns the default settings. Each evaluation script
%   copies this struct and changes only the parameters it varies.
%
%   DAT610 project: CQI-based AMC in the 5G NR downlink (MATLAB 5G Toolbox).

    % Simulation length and randomness
    p.NFrames = 100;                 % 10 ms frames per simulation point (set after timing test)
    p.SNRdB   = 20;                  % SNR (dB), MATLAB per-RE definition
    p.Seed    = 0;                   % random seed for repeatability

    % Carrier (numerology and bandwidth)
    p.CarrierFrequency   = 3.5e9;    % Hz, band n78 (used for Doppler and path loss)
    p.SubcarrierSpacing  = 30;       % kHz -> 0.5 ms slots
    p.NSizeGrid          = 51;       % resource blocks (51 RB at 30 kHz = 20 MHz channel)
    p.ChannelBandwidthHz = 20e6;     % used for spectral efficiency (bit/s/Hz)

    % Antennas: SISO by default (isolates AMC from MIMO rank adaptation)
    % For 2x2 with rank 1: TxPolarizations = 2, RxPolarizations = 2,
    % RIRestriction = [1 0 0 0 0 0 0 0]
    p.TxPanelDimensions = [1 1];
    p.TxPolarizations   = 1;
    p.RxPanelDimensions = [1 1];
    p.RxPolarizations   = 1;
    p.RIRestriction     = [];        % empty = no rank restriction

    % Propagation channel (TR 38.901 TDL models)
    p.DelayProfile = 'TDL-C';        % 'TDL-C' (NLOS) or 'TDL-D' (LOS)
    p.DelaySpread  = 300e-9;         % s
    p.UESpeedKmh   = 3;              % km/h, converted to max Doppler shift

    % Link adaptation: CQI and MCS tables (TS 38.214), keep them equal
    p.CQITable = "Table2";           % "Table1" (64-QAM) or "Table2" (256-QAM)
    p.MCSTable = 'Table2';           % 'Table1' or 'Table2'

    % CSI feedback (CSI-RS period is set equal to the report period)
    p.CSIReportPeriod   = 5;         % slots (allowed: 4,5,8,10,16,20,32,40,64,80,...)
    p.UEProcessingDelay = 7;         % slots (example default)
    p.BSProcessingDelay = 1;         % slots (example default)

    % Receiver
    p.PerfectChannelEstimator   = false;               % practical DM-RS / CSI-RS estimation
    p.LDPCDecodingAlgorithm     = "Normalized min-sum";
    p.MaximumLDPCIterationCount = 6;

    % Fixed MCS (empty = adaptive MCS from CQI)
    % Example: struct('Modulation','64QAM','TargetCodeRate',666/1024)
    p.FixedMCS = [];

    % Distance-to-SNR mapping (Evaluation 2). Assumed values: give a
    % source for each in the report.
    p.BSHeight        = 25;          % m (TR 38.901 UMa)
    p.UEHeight        = 1.5;         % m (TR 38.901 UMa)
    p.TxPowerdBm      = 46;          % dBm, gNB transmit power (assumption)
    p.UENoiseFiguredB = 7;           % dB, UE noise figure (assumption)
end
