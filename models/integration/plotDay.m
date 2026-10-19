function files = plotDay(opts)
%PLOTDAY  The real-day runs side by side: one comparison figure, plus the weather input.
%
%   files = plotDay()                                runs saved by runIntegration("day", ...)
%   files = plotDay(Model="intSystem_aqibPLL")
%
% Reads results/<model>/day_*.mat. x axes are clock time on 6 Oct 2026 (AEST),
% mapped back from the compressed simulation time (gullenProfile).
%   day_weather.png     what went in: irradiance and wind speed, real and as simulated
%   day_comparison.png  PV / wind / Total Power; grid import or export per case; DC bus
%                       per case; and per case the renewable share, bus worst and THD.
% Grid power = site load - Total Power (constant-PQ site load); + = import from the grid.

arguments
    opts.Model (1,1) string = "intSystem_aqibPLL"
    opts.Show  (1,1) logical = false   % true: leave the figures open (zoom, data tips), still saves the PNG
end
P  = intPaths();
rd = P.results;  if opts.Model ~= "intSystem", rd = fullfile(rd, opts.Model); end
fd = fullfile(rd, 'figures', 'Day');  if ~isfolder(fd), mkdir(fd); end
dp = gullenProfile();  xp = intParams();
clock = @(t) dp.t_real(1) + minutes(5*t/dp.step);           % sim s -> clock time

cases = ["day_load_min","day_load_mid","day_load_max","day_shed"];
lbl   = ["50 kW load","150 kW load","250 kW load","250 kW, shed at 10:00"];
col   = [0.20 0.55 0.30; 0.15 0.45 0.75; 0.80 0.35 0.15; 0.45 0.25 0.60];
D = struct([]);
for k = 1:numel(cases)
    f = fullfile(rd, cases(k) + ".mat");
    if ~isfile(f), continue; end
    S = load(f);  L = S.logsout;  s = S.s;  r = S.r;
    xs = xp;  for j = 1:2:numel(s.set), q = strsplit(char(s.set{j}), '.'); xs = setfield(xs, q{:}, s.set{j+1}); end %#ok<SFLD>
    E = L.get('E').Values;  Ed = squeeze(E.Data);  if size(Ed,1) ~= numel(E.Time), Ed = Ed.'; end
    te = E.Time;  n = round(dp.step/median(diff(te)));                 % one 5-min sample
    Pw = movmean(gradient(Ed.', median(diff(te))).', n) / 1e3;          % kW: pv, wind, invdc, ac
    Psite = xs.pcc.site.P/1e3 * (te < xs.pcc.site.t);
    v = L.get('v_dc').Values;
    c = struct('name',cases(k), 'lbl',lbl(k), 'col',col(k,:), 't',te, 'Ppv',Pw(:,1), 'Pw',Pw(:,2), ...
               'Pac',Pw(:,4), 'Pgrid',Psite - Pw(:,4), 'tv',v.Time, 'v',movmean(v.Data(:), round(1e-3/median(diff(v.Time)))), ...
               'r',r, 'share',100*trapz(te, max(0,min(Pw(:,4),Psite))) / max(trapz(te, Psite), eps), 'Psite',Psite);
    D = [D c]; %#ok<AGROW>
end
if isempty(D), error('plotDay:none', 'No day_*.mat in %s', rd); end
files = strings(0);

% ---- the input -------------------------------------------------------------
f = figure('Visible',tern(opts.Show,'on','off'),'Color','w','Position',[100 100 1100 520]);
tiledlayout(f, 2, 1, 'TileSpacing','compact', 'Padding','compact');
nexttile; yyaxis left; plot(dp.t_real, dp.G, 'LineWidth',1.2); ylabel('G [W/m^2]');
yyaxis right; plot(dp.t_real, dp.pv_pu*9.90, ':'); ylabel('Gullen solar farm [MW]'); grid on
title('Irradiance: Gullen Range solar farm (GULLRSF1), 5-min SCADA, scaled to 1000 W/m^2 at its rating');
nexttile; yyaxis left; plot(dp.t_real, dp.v, 'LineWidth',1.2); ylabel('v_{wind} [m/s]');
yyaxis right; plot(dp.t_real, dp.w_pu*265.8, ':'); ylabel('Gullen wind farm [MW]'); grid on
title('Wind: Gullen Range wind farm (GULLRWF1+2), inverted through our turbine''s cubic curve (12 m/s rated)');
sgtitle(f, sprintf('Real day in: 6 Oct 2026, 06:00-14:00 AEST, compressed %.0fx (5 min = %.0f ms of simulation)', ...
    dp.compression, 1e3*dp.step), 'FontSize', 11);
files(end+1) = fullfile(fd, 'day_weather.png');  exportgraphics(f, files(end), 'Resolution', 120);  if ~opts.Show, close(f); end

% ---- the comparison ---------------------------------------------------------
f = figure('Visible',tern(opts.Show,'on','off'),'Color','w','Position',[100 100 1400 900]);
tiledlayout(f, 2, 2, 'TileSpacing','compact', 'Padding','compact');
ref = D(end);  for k = 1:numel(D), if D(k).name == "day_load_max", ref = D(k); end, end
nexttile; hold on
area(clock(ref.t), [ref.Ppv ref.Pw], 'EdgeColor','none', 'FaceAlpha',0.5);
plot(clock(ref.t), ref.Pac, 'k', 'LineWidth',1.5);
yline(150, 'r:', '150 kVA rating');  grid on;  ylabel('P [kW]');  ylim([0 180]);
legend('PV into bus','Wind into bus','Total Power', 'Location','northwest');
title('The plant through the day (same in every case)');

nexttile; hold on
for c = D, plot(clock(c.t), c.Pgrid, 'Color',c.col, 'LineWidth',1.3, 'DisplayName',c.lbl); end
yline(0, 'k-', 'HandleVisibility','off');  grid on;  ylabel('P_{grid} [kW]  (+ import, - export)');
legend('Location','northeast');  title('Grid import / export per case');

nexttile; hold on
for c = D, plot(clock(c.tv), c.v, 'Color',c.col, 'DisplayName',c.lbl); end
yline(xp.Vdc_ref*[0.95 1.05], 'r--', 'HandleVisibility','off');
yline(xp.curt.Vcap, ':', '720 V curtailment', 'HandleVisibility','off');
grid on;  ylabel('v_{dc} [V]');  ylim([660 745]);  legend('Location','southwest');
title('DC bus per case (\pm5 % band dashed)');

nexttile;
M = [[D.share]; arrayfun(@(c) c.r.dev_pct, D); arrayfun(@(c) c.r.THDtot, D)].';
b = bar(categorical(cellstr([D.lbl]), cellstr([D.lbl])), M);
legend('Load met by PV+wind [%]','Bus worst [%] (limit 5)','Grid THD at 10:20 [%] (limit 5)', 'Location','northeast');
grid on;  title('Per case');
for j = 1:numel(b), xtips = b(j).XEndPoints; text(xtips, b(j).YEndPoints, compose('%.1f', b(j).YData), ...
        'HorizontalAlignment','center', 'VerticalAlignment','bottom', 'FontSize',8); end
sgtitle(f, 'Real day (Gullen Range NSW, 6 Oct 2026, 06:00-14:00): same weather, four site-load cases', 'FontSize', 12);
files(end+1) = fullfile(fd, 'day_comparison.png');  exportgraphics(f, files(end), 'Resolution', 120);  if ~opts.Show, close(f); end
end

function v = tern(c, a, b), if c, v = a; else, v = b; end, end
