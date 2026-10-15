%PLOTFIGURES Draw Figs. 1-4 from the saved results (no re-simulation).
%   Follows the course rules: no titles (use LaTeX captions), axis names
%   with units, readable fonts. Saves vector PDFs in figures/.

if ~exist('figures','dir'), mkdir('figures'); end
fontSize = 12;
lw = 1.5;

%% Fig. 1a / 1b: AMC vs fixed MCS over SNR
if isfile(fullfile('results','eval1.mat'))
    S = load(fullfile('results','eval1.mat'));
    isAMC = startsWith(S.caseNames,"AMC");

    % Fig. 1a: throughput vs SNR
    f = figure('Color','w'); hold on; grid on; box on;
    for c = 1:numel(S.caseNames)
        if isAMC(c)
            plot(S.snr, S.thr(c,:), '-o', 'LineWidth', lw+0.5);
        else
            plot(S.snr, S.thr(c,:), '--', 'LineWidth', lw);
        end
    end
    xlabel('SNR (dB)'); ylabel('Throughput (Mb/s)');
    legend(S.caseNames, 'Location','northwest');
    set(gca,'FontSize',fontSize);
    exportgraphics(f, fullfile('figures','fig1a_throughput_vs_snr.pdf'), 'ContentType','vector');

    % Fig. 1b: spectral efficiency vs SNR, with the Shannon bound
    f = figure('Color','w'); hold on; grid on; box on;
    for c = find(isAMC)
        plot(S.snr, S.se(c,:), '-o', 'LineWidth', lw+0.5);
    end
    plot(S.snr, log2(1 + 10.^(S.snr/10)), 'k:', 'LineWidth', lw);
    xlabel('SNR (dB)'); ylabel('Spectral efficiency (bit/s/Hz)');
    legend([S.caseNames(isAMC), "Shannon bound"], 'Location','northwest');
    set(gca,'FontSize',fontSize);
    exportgraphics(f, fullfile('figures','fig1b_spectral_efficiency_vs_snr.pdf'), 'ContentType','vector');
end

%% Fig. 2: throughput vs distance, LOS vs NLOS
if isfile(fullfile('results','eval2.mat'))
    S = load(fullfile('results','eval2.mat'));
    f = figure('Color','w'); hold on; grid on; box on;
    for s = 1:numel(S.scenNames)
        plot(S.dist, S.thr(s,:), '-o', 'LineWidth', lw);
    end
    xlabel('Distance (m)'); ylabel('Throughput (Mb/s)');
    legend(S.scenNames, 'Location','northeast');
    set(gca,'FontSize',fontSize);
    exportgraphics(f, fullfile('figures','fig2_throughput_vs_distance.pdf'), 'ContentType','vector');
end

%% Figs. 3 and 4: throughput and BLER vs UE speed, per CSI report period
if isfile(fullfile('results','eval3.mat'))
    S = load(fullfile('results','eval3.mat'));
    names = "CSI period " + S.periods + " slots";

    f = figure('Color','w'); hold on; grid on; box on;
    for k = 1:numel(S.periods)
        plot(S.speeds, S.thr(k,:), '-o', 'LineWidth', lw);
    end
    xlabel('UE speed (km/h)'); ylabel('Throughput (Mb/s)');
    xticks(S.speeds); legend(names, 'Location','northeast');
    set(gca,'FontSize',fontSize);
    exportgraphics(f, fullfile('figures','fig3_throughput_vs_speed.pdf'), 'ContentType','vector');

    f = figure('Color','w'); hold on; grid on; box on;
    for k = 1:numel(S.periods)
        plot(S.speeds, 100*S.bler(k,:), '-o', 'LineWidth', lw);
    end
    yline(10, 'k--', '10% target', 'LineWidth', 1, 'FontSize', fontSize-1);
    xlabel('UE speed (km/h)'); ylabel('BLER (%)');
    xticks(S.speeds); legend(names, 'Location','northwest');
    set(gca,'FontSize',fontSize);
    exportgraphics(f, fullfile('figures','fig4_bler_vs_speed.pdf'), 'ContentType','vector');
end
