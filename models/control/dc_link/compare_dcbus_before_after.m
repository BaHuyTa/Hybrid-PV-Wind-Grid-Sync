%% compare_dcbus_before_after.m
% DC bus with real PV + wind, with and without the DC bus voltage controller:
%   BEFORE  dc_bus_BEFORE_noController   - controller blocks commented out
%   AFTER   dc_bus_AFTER_withController  - PI_BusCtrl drives the battery source CS_Batt
% Each model takes ~6 min for 1 s, so results are cached in dcbus_compare_results.mat.
% Set rerun = true to simulate both again; otherwise only missing results are run.

rerun = false;
cacheFile = fullfile(pwd, 'dcbus_compare_results.mat');
models = {'dc_bus_BEFORE_noController', 'dc_bus_AFTER_withController'};
labels = {'BEFORE (no controller)', 'AFTER (with controller)'};
cols   = {[0.85 0.2 0.2], [0.1 0.6 0.2]};
V_ref  = 700;

if isfile(cacheFile) && ~rerun, S = load(cacheFile); R = S.R; else, R = struct('t', {}, 'vdc', {}, 'tw', {}, 'iw', {}, 'tb', {}, 'ib', {}); end
for k = 1:2
    if numel(R) >= k && ~isempty(R(k).t) && ~rerun, continue; end
    fprintf('Running %s (about 6 min) ... ', models{k}); tic;
    so = sim(models{k}, 'CaptureErrors', 'on', 'SignalLogging', 'on');
    if ~isempty(so.ErrorMessage), error('%s failed: %s', models{k}, so.ErrorMessage); end
    fprintf('%.0f s\n', toc);
    v = so.logsout.get('V_DC').Values;   R(k).t  = v.Time;  R(k).vdc = v.Data(:);
    w = so.logsout.get('I_wind').Values; R(k).tw = w.Time;  R(k).iw  = w.Data(:);
    R(k).tb = []; R(k).ib = [];
    if k == 2, b = so.logsout.get('I_batt_cmd').Values; R(k).tb = b.Time; R(k).ib = b.Data(:); end
    save(cacheFile, 'R');
end

% wind current is pulsed by its 10 kHz converter: show its 5 ms moving average.
% Resample at 1 us - a 0.1 ms grid equals the PWM period and aliases the pulses.
for k = 1:2
    tg = (0:1e-6:R(k).tw(end))';
    iw = interp1(R(k).tw, R(k).iw, tg, 'previous', 0);
    R(k).twg = tg(1:100:end); iwavg = movmean(iw, 5000); R(k).iwavg = iwavg(1:100:end);
    kk = R(k).t >= R(k).t(end) - 0.1;
    R(k).vend = mean(R(k).vdc(kk));
    fprintf('%-24s V_DC over the last 0.1 s = %.1f V (max %.1f V) | wind current avg (last 0.1 s) = %.1f A\n', ...
        labels{k}, R(k).vend, max(R(k).vdc), mean(iw(tg >= tg(end) - 0.1)));
end

%% figure
fig = figure('Name', 'DC bus controller: before vs after', 'Color', 'w', 'Position', [60 60 1400 820]);
theme(fig, 'light');
tl = tiledlayout(fig, 2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tl, 'DC bus with real PV + wind: without vs with the DC bus voltage controller', 'FontWeight', 'bold');

ax = nexttile(tl, [1 2]); hold(ax, 'on'); grid(ax, 'on');
for k = 1:2, plot(ax, R(k).t, R(k).vdc, 'Color', cols{k}, 'LineWidth', 1.4); end
yline(ax, V_ref, '--k', '700 V setpoint', 'LabelHorizontalAlignment', 'left');
xlabel(ax, 'time (s)'); ylabel(ax, 'DC bus voltage (V)'); title(ax, 'DC bus voltage');
legend(ax, labels, 'Location', 'northwest');

ax = nexttile(tl);
short = {'BEFORE', 'AFTER'};
b = bar(ax, categorical(short, short), [R(1).vend R(2).vend]); b.FaceColor = 'flat'; b.CData = [cols{1}; cols{2}];
hold(ax, 'on'); grid(ax, 'on'); yline(ax, V_ref, '--k', '700 V', 'LineWidth', 1.5);
text(ax, 1:2, [R(1).vend R(2).vend] + 80, {sprintf('%.0f V (%.1fx)', R(1).vend, R(1).vend/V_ref), sprintf('%.1f V', R(2).vend)}, ...
     'HorizontalAlignment', 'center', 'FontWeight', 'bold');
ylim(ax, [0 1.15*max(R(1).vend, V_ref)]); ylabel(ax, 'V'); title(ax, 'Bus voltage at t = 1 s');

ax = nexttile(tl); hold(ax, 'on'); grid(ax, 'on');
plot(ax, R(2).t, R(2).vdc, 'Color', cols{2}, 'LineWidth', 1.2); yline(ax, V_ref, '--k');
ylim(ax, [690 725]); xlabel(ax, 'time (s)'); ylabel(ax, 'V');
title(ax, 'AFTER, zoomed: settles at 700 V');

ax = nexttile(tl); hold(ax, 'on'); grid(ax, 'on');
for k = 1:2, plot(ax, R(k).twg, R(k).iwavg, 'Color', cols{k}, 'LineWidth', 1.3); end
xlabel(ax, 'time (s)'); ylabel(ax, 'A (5 ms average)'); title(ax, 'Wind current into the bus');
legend(ax, labels, 'Location', 'northeast');

ax = nexttile(tl); grid(ax, 'on'); hold(ax, 'on');
plot(ax, R(2).tb, R(2).ib, 'Color', cols{2}, 'LineWidth', 1.3); yline(ax, 0, ':k');
xlabel(ax, 'time (s)'); ylabel(ax, 'A (negative = absorbing)');
title(ax, 'AFTER: battery current command (PI\_BusCtrl)');

exportgraphics(fig, fullfile(pwd, 'compare_dcbus_before_after.png'), 'Resolution', 150);
fprintf('Saved compare_dcbus_before_after.png\n');
