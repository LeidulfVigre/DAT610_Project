%EVAL3_MOBILITY Evaluation 3: outdated CQI, UE speed x CSI report period (Figs. 3-4).
%   Curves: CSI report period 5, 20, 80 slots (2.5, 10, 40 ms at 30 kHz SCS).
%   Fixed: TDL-C 300 ns, SNR 20 dB, AMC with Table 2.
%   Output: results/eval3.mat

p0 = baseConfig();
p0.SNRdB = 20;                                      % dB
speeds  = [3 30 60 120];                            % km/h
periods = [5 20 80];                                % slots

[pi_, vi] = ndgrid(1:numel(periods), 1:numel(speeds));
nJobs = numel(pi_);
out = cell(nJobs,1);

tStart = tic;
parfor k = 1:nJobs
    p = p0;
    p.CSIReportPeriod = periods(pi_(k));
    p.UESpeedKmh      = speeds(vi(k));
    out{k} = runLink(p);
end
fprintf('Evaluation 3 finished in %.1f min\n', toc(tStart)/60);

% Matrices [period x speed]
thr  = reshape(cellfun(@(r) r.ThroughputMbps, out), size(pi_));
bler = reshape(cellfun(@(r) r.BLER,           out), size(pi_));
doppler = reshape(cellfun(@(r) r.MaxDopplerHz, out), size(pi_));

if ~exist('results','dir'), mkdir('results'); end
save(fullfile('results','eval3.mat'), 'speeds','periods','thr','bler','doppler','out','p0');
