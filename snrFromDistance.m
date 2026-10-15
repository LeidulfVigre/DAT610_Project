function snrdB = snrFromDistance(distances, los, p)
%SNRFROMDISTANCE Map gNB-UE distance to link SNR with TR 38.901 UMa path loss.
%   snrdB = snrFromDistance(distances, los, p) returns the SNR (dB) for each
%   horizontal distance (m) in DISTANCES. LOS is true for line of sight,
%   false for non-line of sight. P is the parameter struct from baseConfig().
%
%   SNR = Ptx - PL(d) - (-174 + 10*log10(B) + NF)
%   B is the occupied bandwidth (NSizeGrid * 12 * SCS), so the result
%   matches MATLAB's per-resource-element SNR. Mean path loss only (no
%   shadow fading), antenna gains ignored.
%
%   Based on the MathWorks 5G Toolbox example "Include Path Loss in NR
%   Link-Level Simulations" (nrPathLoss / nrPathLossConfig).

    plConf = nrPathLossConfig;
    plConf.Scenario = 'UMa';

    bsPos = [0; 0; p.BSHeight];                              % m
    B = p.NSizeGrid * 12 * p.SubcarrierSpacing * 1e3;        % Hz (occupied)
    noisedBm = -174 + 10*log10(B) + p.UENoiseFiguredB;       % dBm

    snrdB = zeros(size(distances));
    for k = 1:numel(distances)
        uePos = [distances(k); 0; p.UEHeight];               % m
        pl = nrPathLoss(plConf, p.CarrierFrequency, los, bsPos, uePos);   % dB
        snrdB(k) = p.TxPowerdBm - pl - noisedBm;
    end
end
