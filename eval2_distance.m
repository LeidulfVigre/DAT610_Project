%EVAL2_DISTANCE Evaluation 2: throughput vs distance, LOS vs NLOS (Fig. 2).
%   Distance is mapped to SNR with TR 38.901 UMa path loss.
%   LOS  = TDL-D (100 ns) + UMa LOS path loss
%   NLOS = TDL-C (300 ns) + UMa NLOS path loss
%   Fixed: AMC with Table 2, 3 km/h, CSI report every 5 slots.
%   Output: results/eval2.mat

p0 = baseConfig();
dist = [100 200 300 400 500 750 1000 1500 2000 3000 4000 5000];   % m

scen(1) = struct('Name',"LOS (TDL-D)", 'LOS',true, 'DelayProfile','TDL-D','DelaySpread',100e-9);
scen(2) = struct('Name',"NLOS (TDL-C)",'LOS',false,'DelayProfile','TDL-C','DelaySpread',300e-9);

% SNR per distance for each scenario [scenario x distance]
snrMap = zeros(numel(scen), numel(dist));
for s = 1:numel(scen)
    snrMap(s,:) = snrFromDistance(dist, scen(s).LOS, p0);
end

[sc, di] = ndgrid(1:numel(scen), 1:numel(dist));
nJobs = numel(sc);
out = cell(nJobs,1);

tStart = tic;
parfor k = 1:nJobs
    p = p0;
    s = scen(sc(k));
    p.SNRdB        = snrMap(sc(k), di(k));
    p.DelayProfile = s.DelayProfile;
    p.DelaySpread  = s.DelaySpread;
    out{k} = runLink(p);
end
fprintf('Evaluation 2 finished in %.1f min\n', toc(tStart)/60);

thr  = reshape(cellfun(@(r) r.ThroughputMbps, out), size(sc));
bler = reshape(cellfun(@(r) r.BLER,           out), size(sc));
scenNames = [scen.Name];

if ~exist('results','dir'), mkdir('results'); end
save(fullfile('results','eval2.mat'), 'dist','snrMap','scenNames','thr','bler','out','p0');
