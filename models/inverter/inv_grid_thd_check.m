% inv_grid_thd_check.m
% The graded criterion: current THD at rated output < 5%.
%
% Measured on invPlantSw - the switched model, at rated current, on the
% GRID-side current i2. That is the current the grid actually sees and the one
% the standard is written about; the inverter-side current i1 is deliberately
% allowed to carry ripple, because removing it is the filter's whole job. The
% script reports both so the LCL's effect is visible rather than asserted.
%
% Two THD numbers, because they answer different questions:
%   THD(<=50th)  the grid-code convention (IEEE 519 / AS-NZS 4777.2 quote a
%                harmonic range). 2.5 kHz at 50 Hz fundamental.
%   THD(total)   everything up to Nyquist, so the switching harmonics at
%                f_sw = 10 kHz (the 200th) and 2*f_sw count. Always the larger
%                number, and the honest one to quote for a filter design.
%
% Dead time is modelled (ip.t_dead). Once the LCL has removed the switching
% harmonics, dead time is the dominant distortion left: it produces 5th and 7th
% harmonics, which are below the filter corner and cannot be filtered out. The
% current loop rejects them instead, because they sit inside its bandwidth.
%
% Output: results/inv_grid_thd.png (gitignored - regenerate, don't commit)
%
% Usage:
%   addpath(genpath('models'));
%   inv_grid_thd_check
%
% Owner: Duc Pham

clear; clc;
ip     = invParams();
here   = fileparts(mfilename('fullpath'));
outdir = fullfile(here, 'results');
if ~isfolder(outdir), mkdir(outdir); end

n_cyc  = 5;                                   % whole cycles in the FFT window
t_step = 0.02;
T_stop = 0.20;
t      = (0:ip.Ts_power:T_stop)';
Id_ref = ip.I_pk*double(t >= t_step);         % rated output

fprintf('=== grid current THD at rated output ===\n');
fprintf('  LCL: L1 %.3f mH | Cf %.1f uF (Rd %.2f ohm) | L2 %.3f mH | f_res %.0f Hz\n', ...
        ip.L1*1e3, ip.Cf*1e6, ip.Rd, ip.L2*1e3, ip.f_res);
fprintf('  f_sw %g kHz | dead time %.1f us | rated peak %.1f A\n\n', ...
        ip.f_sw/1e3, ip.t_dead*1e6, ip.I_pk);
tic;
tl = invSim(t, struct('model','invPlantSw', 'Id_ref',Id_ref, 'Iq_ref',0));
fprintf('  simulated %.2f s in %.0f s wall\n\n', T_stop, toc);

%% ---- last n_cyc whole cycles ------------------------------------------
tt  = tl.i2_abc.Time;
N   = round(n_cyc/ip.f_grid/ip.Ts_power);
idx = (numel(tt)-N):(numel(tt)-1);
i1  = tl.i1_abc.Data(idx,1);
i2  = tl.i2_abc.Data(idx,1);

[thd1_50, thd1_tot, A1] = thdOf(i1, N, n_cyc);
[thd2_50, thd2_tot, A2] = thdOf(i2, N, n_cyc);

fprintf('  %-28s %12s %12s\n', '', 'inverter i1', 'grid i2');
fprintf('  %s\n', repmat('-', 1, 54));
fprintf('  %-28s %11.1f A %11.1f A\n', 'fundamental (peak)', A1(2), A2(2));
fprintf('  %-28s %11.1f A %11.1f A\n', 'rms', sqrt(mean(i1.^2)), sqrt(mean(i2.^2)));
fprintf('  %-28s %11.2f %% %11.2f %%\n', 'THD (<= 50th harmonic)', 100*thd1_50, 100*thd2_50);
fprintf('  %-28s %11.2f %% %11.2f %%\n', 'THD (total, to Nyquist)', 100*thd1_tot, 100*thd2_tot);
fprintf('  %-28s %11s   %10.1fx\n', 'LCL attenuation', '-', thd1_tot/thd2_tot);

%% ---- where the distortion sits ----------------------------------------
fprintf('\n  harmonic content of the grid current, %% of fundamental:\n');
fprintf('  %-8s %-11s %-12s %-12s\n', 'order', 'freq [Hz]', 'i1 [%]', 'i2 [%]');
for n = [5 7 11 13 17 19 23 25]
    fprintf('  %-8d %-11.0f %-12.2f %-12.2f\n', n, n*ip.f_grid, ...
            100*A1(n+1)/A1(2), 100*A2(n+1)/A2(2));
end
nsw = round(ip.f_sw/ip.f_grid);
for n = [nsw-2 nsw nsw+2 2*nsw]
    if n+1 <= numel(A1)
        fprintf('  %-8d %-11.0f %-12.2f %-12.2f  <- switching\n', n, n*ip.f_grid, ...
                100*A1(n+1)/A1(2), 100*A2(n+1)/A2(2));
    end
end

%% ---- verdict -----------------------------------------------------------
fprintf('\n  %-34s %6.2f %%   target < 5 %%   %s\n', 'GRID CURRENT THD (total)', ...
        100*thd2_tot, verdict(thd2_tot < 0.05));
fprintf('  %-34s %6.2f %%\n\n', 'GRID CURRENT THD (<= 50th)', 100*thd2_50);

%% ---- figure ------------------------------------------------------------
tms = (tt(idx) - tt(idx(1)))*1e3;
f = figure('Color','w','Position',[100 100 1050 780]);
tiledlayout(f, 3, 1, 'TileSpacing','compact', 'Padding','compact');

nexttile;
plot(tms, tl.i1_abc.Data(idx,:), 'LineWidth', 0.8); grid on;
ylabel('i_1 (A)'); legend('a','b','c','Location','eastoutside');
title(sprintf('Inverter-side current - ripple as designed, THD %.1f %%', 100*thd1_tot));

nexttile;
plot(tms, tl.i2_abc.Data(idx,:), 'LineWidth', 1.1); grid on;
ylabel('i_2 (A)'); xlabel('time (ms)'); legend('a','b','c','Location','eastoutside');
title(sprintf('Grid-side current after the LCL - THD %.2f %%', 100*thd2_tot));

nexttile;
hmax = 60;
hh = 0:hmax;
bar(hh, [100*A1(hh+1)/A1(2), 100*A2(hh+1)/A2(2)], 1.0); grid on;
set(gca,'YScale','log'); ylim([1e-3 200]);
xlabel('harmonic order'); ylabel('% of fundamental');
legend('inverter i_1','grid i_2','Location','northeast');
title('Harmonic spectrum - the LCL corner is at h = ' + string(round(ip.f_res/ip.f_grid)));

try, theme(f,'light'); catch, end
exportgraphics(f, fullfile(outdir,'inv_grid_thd.png'), 'Resolution', 130);
fprintf('  Figure written to %s\n', outdir);

if thd2_tot >= 0.05
    error('inv_grid_thd_check:failed', ...
          'Grid current THD %.2f%% does not meet the < 5%% criterion', 100*thd2_tot);
end
fprintf('\n  PASS.\n');

% -------------------------------------------------------------------------
function [thd50, thdTot, A] = thdOf(x, N, n_cyc)
% Single-sided amplitude spectrum over a whole number of fundamental cycles,
% so every harmonic lands exactly on a bin. A(k) is the amplitude at harmonic
% (k-1); A(2) is the fundamental.
X = fft(x)/N;
A = 2*abs(X(1:floor(N/2)));
A(1) = abs(X(1));                              % DC is not doubled
% harmonic n of the fundamental sits at bin n*n_cyc
hIdx = @(n) n*n_cyc + 1;
fund = A(hIdx(1));
h50  = arrayfun(hIdx, 2:50);
thd50 = sqrt(sum(A(h50).^2))/fund;
% total: everything except DC and the fundamental
tot   = sum(A.^2) - A(1)^2 - fund^2;
thdTot = sqrt(max(tot,0))/fund;
% return A indexed by harmonic order for the caller's table
A = A(hIdx(0:min(floor(N/2/n_cyc)-1, 500)));
end

function s = verdict(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end
