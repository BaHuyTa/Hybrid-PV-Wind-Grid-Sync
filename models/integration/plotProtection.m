function files = plotProtection(names, opts)
%PLOTPROTECTION  One figure per protection-path run (trip, island), PNG into results/figures.
%
%   files = plotProtection()                     "trip" and "island"
%   files = plotProtection("island")
%   files = plotProtection([], Model="intSystem_aqibPLL")   runs saved by runIntegration(..., Model=)
%
% Four panels around the events: what stops (inverter, PV and wind currents),
% the DC bus, the PCC voltage, and the PLL's frequency estimate. Dashed lines
% mark the grid breaker opening and the trip.

arguments
    names = []
    opts.Model (1,1) string = "intSystem"
end
if isempty(names), names = ["trip","island","island_sfs"]; end
P = intPaths();
% same rule as runIntegration: any model other than the reference saves to results/<model>/
if opts.Model ~= "intSystem", P.results = fullfile(P.results, opts.Model); end
figDir = fullfile(P.results, 'figures');
if ~isfolder(figDir), mkdir(figDir); end
xp = intParams();  files = strings(0);

for nm = string(names)
    if ~isfile(fullfile(P.results, nm + ".mat")), continue; end   % island_sfs exists only on SFS builds
    S = load(fullfile(P.results, nm + ".mat"));  L = S.logsout;  s = S.s;
    r = analyseIntegration(L, s);              % re-measure: the saved r may predate a metric fix
    g  = @(n) L.get(n).Values;
    tt = r.prot.t_trip;  ti = r.prot.t_island;
    t0 = min([tt, ti]) - 0.05;  t1 = s.T;
    evt = [ti tt];  evt = evt(~isnan(evt));
    ev = @() arrayfun(@(x) xline(x, '--', 'Color', [0.4 0.4 0.4]), evt);

    f = figure('Visible','off', 'Position',[100 100 1200 820], 'Color','w');
    tiledlayout(f, 2, 2, 'TileSpacing','compact', 'Padding','compact');

    % -- 1. What has to stop ------------------------------------------------
    nexttile; hold on; grid on
    tl  = g('inv_tlm');  q = rows(tl.i_dq);  tq = tl.i_dq.Time;
    n1  = @(ts) round(1e-3/median(diff(ts)));
    plot(tq, movmean(hypot(q(:,1), q(:,2)), n1(tq)), 'LineWidth', 1.4);
    pv = g('i_pv');  wd = g('i_wind');
    plot(pv.Time, movmean(pv.Data(:), n1(pv.Time)), 'LineWidth', 1.4);
    plot(wd.Time, movmean(wd.Data(:), n1(wd.Time)), 'LineWidth', 1.4);
    ev(); xlim([t0 t1]); xlabel('t [s]'); ylabel('A (1 ms average)');
    legend('inverter |i_{dq}| [A pk]', 'PV into bus [A]', 'wind into bus [A]', 'Location','east');
    title(sprintf('Trip at %.2f s: inverter off in %.1f ms, PV %.1f ms, wind %.1f ms', ...
        tt, r.prot.i_inv_off_ms, r.prot.i_pv_off_ms, r.prot.i_wind_off_ms));

    % -- 2. DC bus ---------------------------------------------------------------
    nexttile; hold on; grid on
    v = g('v_dc');  plot(v.Time, v.Data(:), 'k', 'LineWidth', 1.2);
    yline(xp.Vdc_ref*[0.95 1.05], 'r');  ev(); xlim([t0 t1]);
    xlabel('t [s]'); ylabel('v_{dc} [V]');
    title(sprintf('DC bus after the trip: %.1f-%.1f V (%.2f %% worst, limit 5 %%)', ...
        r.prot.Vdc_after, r.prot.dev_after_pct));

    % -- 3. PCC voltage ------------------------------------------------------
    nexttile; hold on; grid on
    vab = rows(tl.v_abc);  t2 = tl.v_abc.Time;  n20 = round(0.02/median(diff(t2)));
    plot(t2, vab(:,1), 'Color', [0.75 0.75 0.75]);
    plot(t2, sqrt(2)*sqrt(movmean(vab(:,1).^2, n20)), 'b', 'LineWidth', 1.4);
    ev(); xlim([t0 t1]); xlabel('t [s]'); ylabel('V');
    legend('v_a at the PCC', '\surd2 x 20 ms RMS', 'Location','southwest');
    if isnan(ti)
        title('PCC voltage: the grid holds it');
    else
        title(sprintf('PCC voltage while islanded %.0f-%.0f %%; < 5 %% %.0f ms after the trip', ...
            r.prot.Vpcc_island_pct, r.prot.Vpcc_off_ms));
    end

    % -- 4. Frequency the PLL sees ------------------------------------------
    nexttile; hold on; grid on
    wh = g('w_hat');  plot(wh.Time, wh.Data(:)/(2*pi), 'LineWidth', 1.2);
    yline([47 52], 'r');  ev(); xlim([t0 t1]);  ylim([45 54]);
    xlabel('t [s]'); ylabel('f_{hat} [Hz]');
    if isnan(ti)
        title('PLL frequency estimate (limits 47 / 52 Hz)');
    elseif r.prot.f_island(1) >= 47 && r.prot.f_island(2) <= 52
        title(sprintf('Islanded, f_{hat} %.2f-%.2f Hz: inside 47-52, passive protection is blind', r.prot.f_island));
    else
        % SFS pushed f out of the band, so the relay (not the stand-in) caught the island
        title(sprintf('Islanded, f_{hat} pushed out of 47-52: relay trips %.1f ms after the island', r.prot.detect_ms));
    end

    sgtitle(f, sprintf('%s  -  %s', nm, s.why), 'FontSize', 11, 'Interpreter', 'none');   % "island_sfs" is not a subscript
    files(end+1) = fullfile(figDir, nm + ".png"); %#ok<AGROW>
    exportgraphics(f, files(end), 'Resolution', 110);  close(f);
end
end

function x = rows(ts)
x = squeeze(ts.Data);
if size(x,1) ~= numel(ts.Time), x = x.'; end
end
