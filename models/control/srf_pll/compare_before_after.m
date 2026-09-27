%% compare_before_after.m
% Runs the switched inverter twice on the same distorted grid (5% 5th + 3% 7th)
% and puts the results in one figure:
%   BEFORE  invPlantSw_BEFORE_noPLL  - grid angle straight from atan2 (GridAngle_ideal)
%   AFTER   invPlantSw_AFTER_SRFPLL  - grid angle from the SRF-PLL
% Measurement window: 0.11-0.15 s, i.e. two grid cycles at rated current.
% Run after addpath(genpath('models')) from the repo root (uses invLib/invParams from models/inverter).
% Takes about 2 minutes (two ~50 s runs). Saves compare_before_after.png.

models = {'invPlantSw_BEFORE_noPLL', 'invPlantSw_AFTER_SRFPLL'};
labels = {'BEFORE (no PLL)', 'AFTER (SRF-PLL)'};
angSig = {'theta_ideal', 'theta_pll'};     % the angle that drives the current loop
cols   = {[0.85 0.2 0.2], [0.1 0.6 0.2]};
t_win  = [0.11 0.15];
thd_limit = 5;                            % %, grid-current THD criterion

R = struct();
for k = 1:2
    fprintf('Running %s ... ', models{k}); tic;
    so = sim(models{k}, 'CaptureErrors', 'on');
    if ~isempty(so.ErrorMessage), error('%s failed: %s', models{k}, so.ErrorMessage); end
    fprintf('%.0f s\n', toc);

    % grid current, phase A, over the window
    ia = so.logsout.get('ia_grid').Values;
    sel = ia.Time >= t_win(1) & ia.Time < t_win(2);
    R(k).t  = ia.Time(sel);
    R(k).ia = ia.Data(sel);

    % harmonics and THD (up to the 50th)
    dt = mean(diff(R(k).t)); N = numel(R(k).ia);
    X  = abs(fft(R(k).ia - mean(R(k).ia)))/N*2;
    f  = (0:N-1)'/(N*dt);
    h  = arrayfun(@(n) X(find(abs(f - 50*n) == min(abs(f - 50*n)), 1)), 1:50);
    R(k).h   = 100*h/h(1);                               % % of fundamental
    R(k).thd = 100*sqrt(sum(h(2:50).^2))/h(1);

    % angle wobble: unwrapped angle minus a straight line = deviation from a clean 50 Hz ramp
    th = so.logsout.get(angSig{k}).Values;
    sel = th.Time >= t_win(1) & th.Time < t_win(2);
    tt = th.Time(sel); ph = unwrap(squeeze(th.Data(sel)));
    p = polyfit(tt, ph, 1);
    R(k).tth = tt;
    R(k).wob = (ph - polyval(p, tt))*180/pi;             % degrees

    fprintf('   %-16s THD = %.2f %%   5th = %.2f %%   7th = %.2f %%   angle wobble = %.2f deg pk-pk\n', ...
        labels{k}, R(k).thd, R(k).h(5), R(k).h(7), max(R(k).wob) - min(R(k).wob));
end

%% figure
fig = figure('Name', 'SRF-PLL: before vs after', 'Color', 'w', 'Position', [80 80 1300 800]);
theme(fig, 'light');                      % readable in reports even if MATLAB is in dark mode
tl = tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tl, 'Switched inverter on a distorted grid (5% 5th + 3% 7th): direct atan2 angle vs SRF-PLL', 'FontWeight', 'bold');

% 1) grid current
ax = nexttile(tl); hold(ax, 'on'); grid(ax, 'on');
for k = 1:2, plot(ax, 1e3*R(k).t, R(k).ia, 'Color', cols{k}, 'LineWidth', 1.3); end
xlabel(ax, 'time (ms)'); ylabel(ax, 'grid current i_a (A)');
title(ax, 'Grid current, phase A, at rated current');
legend(ax, labels, 'Location', 'southoutside', 'Orientation', 'horizontal');

% 2) angle wobble
ax = nexttile(tl); hold(ax, 'on'); grid(ax, 'on');
for k = 1:2, plot(ax, 1e3*R(k).tth, R(k).wob, 'Color', cols{k}, 'LineWidth', 1.3); end
xlabel(ax, 'time (ms)'); ylabel(ax, 'deviation from a clean 50 Hz ramp (deg)');
title(ax, 'Grid angle used by the current loop');
legend(ax, {sprintf('%s: %.2f deg pk-pk', labels{1}, max(R(1).wob)-min(R(1).wob)), ...
            sprintf('%s: %.2f deg pk-pk', labels{2}, max(R(2).wob)-min(R(2).wob))}, ...
       'Location', 'southoutside', 'Orientation', 'horizontal');

% 3) harmonic spectrum
ax = nexttile(tl);
orders = [3 5 7 9 11 13];
b = bar(ax, orders, [R(1).h(orders); R(2).h(orders)]', 'grouped');
b(1).FaceColor = cols{1}; b(2).FaceColor = cols{2}; grid(ax, 'on');
xlabel(ax, 'harmonic order'); ylabel(ax, '% of fundamental');
title(ax, 'Harmonics in the grid current');
legend(ax, labels, 'Location', 'northeast');

% 4) THD vs limit
ax = nexttile(tl);
b = bar(ax, categorical(labels, labels), [R(1).thd R(2).thd]);
b.FaceColor = 'flat'; b.CData = [cols{1}; cols{2}]; hold(ax, 'on'); grid(ax, 'on');
yline(ax, thd_limit, '--k', sprintf('%g %% limit', thd_limit), 'LineWidth', 1.5, 'LabelHorizontalAlignment', 'left');
text(ax, 1:2, [R(1).thd R(2).thd] + 0.25, ...
     {sprintf('%.2f %%  FAIL', R(1).thd), sprintf('%.2f %%  PASS', R(2).thd)}, ...
     'HorizontalAlignment', 'center', 'FontWeight', 'bold');
ylim(ax, [0 max(7, 1.2*R(1).thd)]); ylabel(ax, 'THD (%)');
title(ax, 'Grid-current THD at rated current');

exportgraphics(fig, fullfile(pwd, 'compare_before_after.png'), 'Resolution', 150);
fprintf('Saved compare_before_after.png\n');
