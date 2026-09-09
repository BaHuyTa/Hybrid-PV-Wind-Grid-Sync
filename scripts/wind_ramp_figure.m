% wind_ramp_figure.m
% Plots scenario S3 (sustained ramp 4 -> 12 m/s) with both MPPT modes
% overlaid: wind speed, tip-speed ratio against lambda_opt, and P_dc against
% the achievable power. This is the picture behind the "P&O fails on a ramp"
% finding in docs/wind-model-spec.md section 2.
%
% Output: results/s3_ramp.png (results/ is gitignored - regenerate, don't commit)
%
% Usage:
%   addpath(genpath('params'), genpath('scripts'), genpath('models'));
%   wind_ramp_figure
%
% Owner: Ba Huy Ta

clear; clc;
wp = windParams();

t = (0:0.05:300)';
v = min(max(4 + 8*(t-30)/180, 4), 12);            % same profile as wind_scenarios S3
eta_conv = 0.956;                                   % plant conversion at the MPP (wind_mppt_sweep)
P_ach = @(vv) eta_conv*0.5*wp.rho*wp.A*wp.Cp_max*vv.^3;

tlP = windSim(t, v, struct('override', struct('mppt_mode',0)));
tlT = windSim(t, v, struct('override', struct('mppt_mode',1)));

% Tracking efficiency over the settled window, on each run's own time base
eff = @(tl) 100*mean(tl.P_dc.Data(tl.P_dc.Time >= 60)) / ...
             mean(P_ach(interp1(t, v, tl.P_dc.Time(tl.P_dc.Time >= 60))));
fprintf('S3 tracking, t >= 60 s:  P&O %.1f%%   torque control %.1f%%\n', eff(tlP), eff(tlT));

f = figure('Color','w','Position',[100 100 1400 900]);
tiledlayout(f, 3, 1, 'TileSpacing','compact', 'Padding','compact');
cPO = [0.85 0.33 0.10]; cTC = [0 0.45 0.74];

ax1 = nexttile; plot(t, v, 'k', 'LineWidth', 1.5); ylabel('wind (m/s)'); grid on; ylim([3 13]);
title(sprintf('Scenario S3: sustained ramp 4 \\rightarrow 12 m/s, %.0f kW wind branch (averaged model)', wp.P_elec/1e3));

ax2 = nexttile;
plot(tlP.lambda.Time, tlP.lambda.Data, 'Color', cPO, 'LineWidth', 1.5); hold on;
plot(tlT.lambda.Time, tlT.lambda.Data, 'Color', cTC, 'LineWidth', 1.5);
yline(wp.lam_opt, '--k', '\lambda_{opt}');
ylabel('tip-speed ratio \lambda'); grid on; ylim([3 10]);
legend({'P&O', 'torque control'}, 'Location', 'southwest');

ax3 = nexttile;
plot(t, P_ach(v)/1e3, ':k', 'LineWidth', 1.2); hold on;
plot(tlP.P_dc.Time, tlP.P_dc.Data/1e3, 'Color', cPO, 'LineWidth', 1.5);
plot(tlT.P_dc.Time, tlT.P_dc.Data/1e3, 'Color', cTC, 'LineWidth', 1.5);
ylabel('P_{dc} (kW)'); xlabel('time (s)'); grid on;
legend({'achievable', 'P&O', 'torque control'}, 'Location', 'northwest');

linkaxes([ax1 ax2 ax3], 'x'); xlim([0 300]);

outDir = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'results');
if ~exist(outDir, 'dir'), mkdir(outDir); end
out = fullfile(outDir, 's3_ramp.png');
exportgraphics(f, out, 'Resolution', 130);
fprintf('saved %s\n', out);
