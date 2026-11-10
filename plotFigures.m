if ~isfolder(fullfile(pwd,'figures')), mkdir(fullfile(pwd,'figures')); end

fontSize = 8;          % pt, matches IEEE caption size
lw = 1;                % line width
ms = 3;                % marker size
W = 8.8; H = 5.2;      % cm, one IEEE column

%% Fig. 1a / 1b: AMC vs fixed MCS over SNR
if isfile(fullfile('results','eval1.mat'))
    S = load(fullfile('results','eval1.mat'));
    isAMC = startsWith(S.caseNames,"AMC");

    % Fig. 1a: throughput vs SNR
    f = newFig(W,H);
    for c = 1:numel(S.caseNames)
        if isAMC(c)
            plot(S.snr, S.thr(c,:), '-o', 'LineWidth', lw+0.5, 'MarkerSize', ms);
        else
            plot(S.snr, S.thr(c,:), '--', 'LineWidth', lw);
        end
    end
    xlabel('SNR (dB)'); ylabel('Throughput (Mb/s)');
    legend(S.caseNames, 'Location','northwest', 'FontSize', fontSize-1);
    finishFig(f, fontSize, fullfile('figures','fig1a_throughput_vs_snr.pdf'));

    % Fig. 1b: spectral efficiency vs SNR, with the Shannon bound
    f = newFig(W,H);
    for c = find(isAMC)
        plot(S.snr, S.se(c,:), '-o', 'LineWidth', lw+0.5, 'MarkerSize', ms);
    end
    plot(S.snr, log2(1 + 10.^(S.snr/10)), 'k:', 'LineWidth', lw);
    xlabel('SNR (dB)'); ylabel('Spectral efficiency (bit/s/Hz)');
    legend([S.caseNames(isAMC), "Shannon bound"], 'Location','northwest', 'FontSize', fontSize-1);
    finishFig(f, fontSize, fullfile('figures','fig1b_spectral_efficiency_vs_snr.pdf'));
end

%% Fig. 2: throughput vs distance, LOS vs NLOS (CQI Table 2 only)
if isfile(fullfile('results','eval2.mat'))
    S = load(fullfile('results','eval2.mat'));
    keep = find(contains(S.scenNames,"Table 2"));      % file with Table 1/2 runs
    if isempty(keep), keep = 1:numel(S.scenNames); end % older file (2 scenarios)
    names = ["LOS (TDL-D)", "NLOS (TDL-C)"];
    f = newFig(W,H);
    for k = 1:numel(keep)
        plot(S.dist, S.thr(keep(k),:), '-o', 'LineWidth', lw, 'MarkerSize', ms);
    end
    xlabel('Distance (m)'); ylabel('Throughput (Mb/s)');
    legend(names, 'Location','northeast', 'FontSize', fontSize-1);
    finishFig(f, fontSize, fullfile('figures','fig2_throughput_vs_distance.pdf'));
end

%% Figs. 3 and 4: throughput and BLER vs UE speed, per CSI report period
if isfile(fullfile('results','eval3.mat'))
    S = load(fullfile('results','eval3.mat'));
    names = "CSI period " + S.periods + " slots";

    % Fig. 3: throughput vs UE speed
    f = newFig(W,H);
    for k = 1:numel(S.periods)
        plot(S.speeds, S.thr(k,:), '-o', 'LineWidth', lw, 'MarkerSize', ms);
    end
    xlabel('UE speed (km/h)'); ylabel('Throughput (Mb/s)');
    xticks(S.speeds); ylim([0 40]);
    legend(names, 'Location','southwest', 'FontSize', fontSize-1);
    finishFig(f, fontSize, fullfile('figures','fig3_throughput_vs_speed.pdf'));

    % Fig. 4: BLER vs UE speed
    f = newFig(W,H);
    for k = 1:numel(S.periods)
        plot(S.speeds, 100*S.bler(k,:), '-o', 'LineWidth', lw, 'MarkerSize', ms);
    end
    yline(10, 'k--', '10% target', 'LineWidth', 1, 'FontSize', fontSize-1, ...
        'LabelHorizontalAlignment','left');
    xlabel('UE speed (km/h)'); ylabel('BLER (%)');
    xticks(S.speeds);
    legend(names, 'Location','southeast', 'FontSize', fontSize-1);
    finishFig(f, fontSize, fullfile('figures','fig4_bler_vs_speed.pdf'));
end

%% ------------------------------------------------------------------------
function f = newFig(W, H)
% New figure at its printed size (cm), white background, grid on.
f = figure('Color','w', 'Units','centimeters', 'Position',[2 2 W H]);
hold on; grid on; box on;
end

function finishFig(f, fontSize, file)
% Set fonts, remove white margins and the legend box, and export as PDF.
ax = gca;
set(ax, 'FontSize', fontSize, 'LooseInset', [0 0 0 0]);
lg = findobj(f, 'Type', 'Legend');
if ~isempty(lg), lg.Box = 'off'; end
exportgraphics(f, file, 'ContentType','vector');
end