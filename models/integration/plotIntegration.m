function files = plotIntegration(names)
%PLOTINTEGRATION  One figure per saved scenario run, PNG into ../results/figures.
%
%   files = plotIntegration()                  every ../results/*.mat
%   files = plotIntegration(["nominal","cloud"])
%
% Four panels: power flow (from the energy meters), the DC bus against its
% +/-1 % and +/-5 % bands, the grid current at the end of the window, and the
% harmonic spectrum with THD.
%

P      = intPaths();
resDir = P.results;
figDir = fullfile(resDir, 'figures');
if ~isfolder(figDir), mkdir(figDir); end
if nargin == 0 || isempty(names)
    d = dir(fullfile(resDir, '*.mat'));  names = erase(string({d.name}), ".mat");
end
xp = intParams();
files = strings(0);

for nm = string(names)
    S = load(fullfile(resDir, nm + ".mat"));
    L = S.logsout;  s = S.s;  r = S.r;
    f = figure('Visible','off', 'Position',[100 100 1200 820], 'Color','w');
    tiledlayout(f, 2, 2, 'TileSpacing','compact', 'Padding','compact');

    % -- 1. Power flow ----------------------------------------------------
    nexttile;
    E  = L.get('E').Values;  Ed = squeeze(E.Data);  if size(Ed,1) ~= numel(E.Time), Ed = Ed.'; end
    dt = median(diff(E.Time));
    P  = movmean(gradient(Ed.', dt).', round(0.005/dt)) / 1e3;   % 5 ms average
    plot(E.Time, P(:,1), E.Time, P(:,2), E.Time, P(:,4), 'LineWidth', 1.2); hold on
    yline(150, ':', '150 kVA rating', 'LabelHorizontalAlignment','left');
    grid on; xlabel('t [s]'); ylabel('P [kW]'); ylim([0 max(180, max(P(:,4))*1.1)]);
    legend('PV into bus','Wind into bus','Inverter to grid (AC)', 'Location','best');
    title('Power flow (5 ms average of dE/dt)');

    % -- 2. DC bus ----------------------------------------------------------
    nexttile;
    v = L.get('v_dc').Values;
    plot(v.Time, v.Data, 'k', 'LineWidth', 1); hold on
    yline(xp.Vdc_ref*[0.99 1.01], '--', 'Color',[0.2 0.6 0.2]);
    yline(xp.Vdc_ref*[0.95 1.05], '-',  'Color',[0.85 0.3 0.2]);
    grid on; xlabel('t [s]'); ylabel('v_{dc} [V]');
    title(sprintf('DC bus: worst %.1f %% (limit 5 %%), recovery %s ms', ...
        r.dev_pct, strjoin(compose('%.0f', 1e3*r.recover), ' / ')));
    for te = r.events(2:end), xline(te, ':', 'Color',[0.4 0.4 0.4]); end

    % -- 3. Grid current, last 40 ms of the window ---------------------------
    nexttile;
    tl = L.get('inv_tlm').Values;  i2 = squeeze(tl.i2_abc.Data);
    if size(i2,1) ~= numel(tl.i2_abc.Time), i2 = i2.'; end
    tt = tl.i2_abc.Time;  m = tt >= s.window(2) - 0.04 & tt < s.window(2);
    plot(tt(m)*1e3, i2(m,:), 'LineWidth', 1);
    grid on; xlabel('t [ms]'); ylabel('i_{grid} [A]');
    title(sprintf('Grid current (PCC side of the LCL): %.0f A pk', r.I1_pk));
    legend('a','b','c', 'Location','best');

    % -- 4. Spectrum -------------------------------------------------------------
    nexttile;
    bar(2:50, r.h, 'FaceColor',[0.3 0.45 0.7]); grid on
    xlabel('harmonic order'); ylabel('% of fundamental');
    title(sprintf('Grid current THD %.2f %% total, %.2f %% to 50th (limit 5 %%)', ...
        r.THDtot, r.THD50));

    sgtitle(f, sprintf('%s  -  %s', s.name, s.why), 'Interpreter','none', 'FontSize', 11);
    fn = fullfile(figDir, nm + ".png");
    exportgraphics(f, fn, 'Resolution', 130);
    close(f);
    files(end+1) = fn; %#ok<AGROW>
end
end
