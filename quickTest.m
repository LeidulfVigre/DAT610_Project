%QUICKTEST Timing test and sanity checks before the real runs.
%   1) Times one simulation point and estimates the total runtime.
%   2) Checks that AMC behaves as expected (see README, validation).

testFrames = 5;                                     % short run

%% 1) Timing
p = baseConfig();
p.NFrames = testFrames;
tic; r = runLink(p); t = toc;
fprintf('One point, %d frames: %.1f s\n', testFrames, t);

nPoints = 90 + 20 + 12;                             % Eval. 1 + 2 + 3
for nf = [50 100 200]
    fprintf('  Estimated total with %3d frames/point: %.1f h (serial)\n', ...
        nf, nPoints * t * nf/testFrames / 3600);
end

%% 2) Sanity checks
% a) High SNR, low speed, Table 2: 256-QAM should dominate
p = baseConfig(); p.NFrames = testFrames; p.SNRdB = 30;
r = runLink(p);
fprintf('\nSNR 30 dB, 3 km/h, Table 2: %.1f Mb/s, BLER %.1f %%\n', r.ThroughputMbps, 100*r.BLER);
fprintf('  Modulation share QPSK/16/64/256-QAM: %s\n', mat2str(round(100*r.ModulationShare)));

% b) Moderate SNR, low speed: BLER should be near 10 %
p = baseConfig(); p.NFrames = testFrames; p.SNRdB = 15;
r = runLink(p);
fprintf('SNR 15 dB, 3 km/h: BLER %.1f %% (expect around 10 %%)\n', 100*r.BLER);

% c) Distance mapping: SNR should fall with distance, LOS above NLOS
d = [100 500 1000];
fprintf('SNR at %s m  LOS: %s dB  NLOS: %s dB\n', mat2str(d), ...
    mat2str(round(snrFromDistance(d,true,baseConfig()),1)), ...
    mat2str(round(snrFromDistance(d,false,baseConfig()),1)));
