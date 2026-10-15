%EVAL1_SNR Evaluation 1: AMC vs fixed MCS over SNR (Fig. 1).
%   Curves: AMC with CQI/MCS Table 1, AMC with Table 2, and four fixed MCS.
%   Fixed: TDL-C 300 ns, 3 km/h, CSI report every 5 slots.
%   Output: results/eval1.mat

p0 = baseConfig();
snr = -5:2.5:30;                                   % dB

% Fixed MCS rows from MCS Table 2 (TS 38.214 Table 5.1.3.1-2):
% MCS 3, 7, 15, 23. Check the values with nrPDSCHMCSTables before use.
fixedMCS = { 'QPSK',   449/1024;
             '16QAM',  490/1024;
             '64QAM',  666/1024;
             '256QAM', 797/1024 };

% Define the cases (curves)
cases = struct('Name',{},'CQITable',{},'MCSTable',{},'FixedMCS',{});
cases(end+1) = struct('Name',"AMC, Table 1 (64-QAM)", 'CQITable',"Table1",'MCSTable','Table1','FixedMCS',[]);
cases(end+1) = struct('Name',"AMC, Table 2 (256-QAM)",'CQITable',"Table2",'MCSTable','Table2','FixedMCS',[]);
for m = 1:size(fixedMCS,1)
    fm = struct('Modulation',fixedMCS{m,1},'TargetCodeRate',fixedMCS{m,2});
    cases(end+1) = struct('Name',"Fixed " + fixedMCS{m,1} + sprintf(", R = %.2f",fixedMCS{m,2}), ...
        'CQITable',"Table2",'MCSTable','Table2','FixedMCS',fm); %#ok<SAGROW>
end

% All (case, SNR) combinations as independent jobs
[ci, si] = ndgrid(1:numel(cases), 1:numel(snr));
nJobs = numel(ci);
out = cell(nJobs,1);

tStart = tic;
parfor k = 1:nJobs                                  % falls back to for without PCT
    p = p0;
    c = cases(ci(k));
    p.SNRdB    = snr(si(k));
    p.CQITable = c.CQITable;
    p.MCSTable = c.MCSTable;
    p.FixedMCS = c.FixedMCS;
    out{k} = runLink(p);
end
fprintf('Evaluation 1 finished in %.1f min\n', toc(tStart)/60);

% Collect into matrices [case x SNR]
thr  = reshape(cellfun(@(r) r.ThroughputMbps,     out), size(ci));
se   = reshape(cellfun(@(r) r.SpectralEfficiency, out), size(ci));
bler = reshape(cellfun(@(r) r.BLER,               out), size(ci));
caseNames = [cases.Name];

if ~exist('results','dir'), mkdir('results'); end
save(fullfile('results','eval1.mat'), 'snr','caseNames','thr','se','bler','out','p0');
