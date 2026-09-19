% inv_thd_check.m
% Validation of the switched 120-degree bridge: does it produce what the
% closed form in invParams.m says it should, and what is the spectrum?
%
% Two things at once, because they read the same FFT window:
%   1. Measured vs closed form - rms, fundamental, THD, pole levels, phase
%      sequence. 120-degree conduction has an exact answer, so this is a real
%      check rather than a plausibility glance. Errors should be about -0.25%,
%      which is the IGBT and diode forward drops (2 devices x 0.8 V of 700 V).
%   2. The harmonic spectrum: 6k+/-1 only, no even, no triplen, h-th harmonic
%      at 1/h of the fundamental. This is the number the LCL work starts from.
%
% Telemetry is logged at the solver step and is uniformly sampled, so unlike
% the wind THD check there is no Simscape log to resample - the FFT window is
% a whole number of cycles taken straight off the bus.
%
% Output: results/inv_120deg_waveforms.png, results/inv_120deg_spectrum.png
%         (gitignored - regenerate, do not commit)
%
% Usage:
%   addpath(genpath('models'));
%   inv_thd_check
%
% Owner: Duc Pham

clear; clc;
ip   = invParams();
here = fileparts(mfilename('fullpath'));
outdir = fullfile(here, 'results');
if ~isfolder(outdir), mkdir(outdir); end

n_cyc  = 5;
T_stop = n_cyc/ip.f_grid;
t = (0:ip.Ts_power:T_stop)';

fprintf('=== switched 120-degree bridge, %d cycles at %g Hz ===\n', n_cyc, ip.f_grid);
tic;
tl = invSim(t, struct('model','invBridge120'));
fprintf('simulated %.3f s in %.0f s wall\n\n', T_stop, toc);

%% ---- last whole cycle -------------------------------------------------
N   = round((1/ip.f_grid)/ip.Ts_power);       % samples per fundamental cycle
idx = (numel(t)-N):(numel(t)-1);
tc  = t(idx);

vp  = tl.v_pole.Data(idx,:);
vph = tl.v_phase.Data(idx,:);
vll = tl.v_line.Data(idx,:);
il  = tl.i_load.Data(idx,:);
g   = tl.gates.Data(idx,:);

rmsOf = @(x) sqrt(mean(x.^2));
fund  = @(x) (2/N)*sum(x(:).'.*exp(-1j*2*pi*(0:N-1)/N));   % complex, peak-valued

Van_rms  = rmsOf(vph(:,1));
Van1_rms = abs(fund(vph(:,1)))/sqrt(2);
Vab_rms  = rmsOf(vll(:,1));
Vab1_rms = abs(fund(vll(:,1)))/sqrt(2);
Ia_rms   = rmsOf(il(:,1));
THD_ph   = sqrt(max(Van_rms^2 - Van1_rms^2, 0))/Van1_rms;
P_load   = 3*Ia_rms^2*ip.R_load;

%% ---- 1. measured vs closed form ---------------------------------------
rows = { ...
  'phase voltage V_an rms  (V)', Van_rms,    ip.V_ph_rms; ...
  'phase fundamental  rms  (V)', Van1_rms,   ip.V_ph1_rms; ...
  'line voltage  V_ab rms  (V)', Vab_rms,    ip.V_ll_rms; ...
  'line fundamental   rms  (V)', Vab1_rms,   ip.V_ll1_rms; ...
  'load current  i_a  rms  (A)', Ia_rms,     ip.I_ph_rms; ...
  'phase voltage THD       (%)', 100*THD_ph, 100*ip.THD_ph; ...
  'load power             (kW)', P_load/1e3, ip.P_load/1e3};

fprintf('=== 1. measured vs closed form ===\n');
fprintf('  %-30s %10s %10s %9s\n', 'quantity', 'measured', 'theory', 'error');
fprintf('  %s\n', repmat('-', 1, 62));
worst = 0;
for k = 1:size(rows,1)
    m = rows{k,2}; th = rows{k,3}; e = 100*(m-th)/th;
    worst = max(worst, abs(e));
    fprintf('  %-30s %10.2f %10.2f %8.2f%%\n', rows{k,1}, m, th, e);
end
fprintf('\n  worst error %.2f%% - device drops account for %.2f%%\n\n', ...
        worst, 100*2*ip.Vf_dev/ip.V_dc);
assert(worst < 1.0, 'measured output is more than 1%% off the closed form');

%% ---- 2. pole levels and phase sequence --------------------------------
lev = uniquetol(round(vp(:,1),1), 0.02, 'DataScale', ip.V_dc);
fprintf('=== 2. switching pattern ===\n');
fprintf('  pole voltage V_a0 levels : %s V   (expect 0, %g, %g)\n', ...
        mat2str(round(sort(lev(:).'),1)), ip.V_dc/2, ip.V_dc);
assert(numel(lev) == 3, 'pole voltage should take exactly three levels');

ang = rad2deg(angle([fund(vph(:,1)) fund(vph(:,2)) fund(vph(:,3))]));
seq = mod(ang - ang(1), 360);
fprintf('  fundamental angles rel. a: %6.1f %6.1f %6.1f deg\n', seq);
assert(abs(seq(2)-240) < 2 && abs(seq(3)-120) < 2, ...
       'phase sequence is not a-b-c - check the gate order');
fprintf('  phase sequence           : a-b-c (positive)\n');

dwell = sum(g(:,1))/N*360;
fprintf('  gate G1 conduction       : %.1f deg (expect 120)\n\n', dwell);
assert(abs(dwell-120) < 1, 'conduction angle is not 120 deg');

%% ---- 3. spectrum ------------------------------------------------------
X  = abs(fft(vph(:,1)))*2/N;  X = X(1:floor(N/2))/sqrt(2);   % single-sided rms
h  = (0:numel(X)-1)';
fprintf('=== 3. phase voltage spectrum ===\n');
fprintf('  %-8s %-11s %-11s %-11s %s\n', 'order', 'freq [Hz]', 'rms [V]', 'theory', '% of fund');
for n = [1 3 5 7 9 11 13]
    th = 0; if mod(n,2) == 1 && mod(n,3) ~= 0, th = ip.V_ph1_rms/n; end
    fprintf('  %-8d %-11.0f %-11.2f %-11.2f %.1f\n', ...
            n, n*ip.f_grid, X(n+1), th, 100*X(n+1)/X(2));
end
% harmonic n sits in bin n+1
triplen = X([3 9 15]+1);           % 3rd, 9th, 15th
even    = X([2 4 6]+1);            % 2nd, 4th, 6th
fprintf('\n  largest triplen %.3f V, largest even %.3f V (both should be ~0)\n\n', ...
        max(triplen), max(even));
assert(max([triplen; even]) < 0.01*X(2), 'unexpected even or triplen harmonics');

%% ---- figures ----------------------------------------------------------
tms = (tc - tc(1))*1e3;
f1 = figure('Color','w','Position',[100 100 980 820]);
tiledlayout(f1, 5, 1, 'TileSpacing','compact', 'Padding','compact');

nexttile; stairs(tms, g + (0:5)*1.4, 'LineWidth', 1); grid on; ylim([-0.3 8]);
yticks((0:5)*1.4 + 0.5); yticklabels({'G1 a+','G2 a-','G3 b+','G4 b-','G5 c+','G6 c-'});
title('Gate pulses - 120 deg conduction, 60 deg gap per leg, no dead time needed');

nexttile; plot(tms, vp, 'LineWidth', 1.1); grid on; ylabel('V_{a0,b0,c0} (V)');
legend('a','b','c','Location','eastoutside');
title('Pole voltages (to DC-): three levels 0 / V_{dc}/2 / V_{dc}');

nexttile; plot(tms, vph, 'LineWidth', 1.1); grid on; ylabel('V_{an,bn,cn} (V)');
legend('a','b','c','Location','eastoutside');
title('Load phase voltages: 120 deg quasi-square - the signature of 120 deg mode');

nexttile; plot(tms, vll, 'LineWidth', 1.1); grid on; ylabel('V_{ab,bc,ca} (V)');
legend('ab','bc','ca','Location','eastoutside');
title('Line-to-line voltages: six-step');

nexttile; plot(tms, il, 'LineWidth', 1.1); grid on; ylabel('i_{a,b,c} (A)');
xlabel('time (ms)'); legend('a','b','c','Location','eastoutside');
title('Load currents (resistive load, so they follow the phase voltages)');

try, theme(f1,'light'); catch, end
exportgraphics(f1, fullfile(outdir,'inv_120deg_waveforms.png'), 'Resolution', 130);

keep = h <= 25;
f2 = figure('Color','w','Position',[120 120 860 430]);
bar(h(keep), X(keep), 0.5); grid on;
xlabel('harmonic order'); ylabel('rms (V)');
title(sprintf('V_{an} spectrum - THD %.2f%%, 6k\\pm1 only, lowest at %g Hz', ...
      100*THD_ph, 5*ip.f_grid));
try, theme(f2,'light'); catch, end
exportgraphics(f2, fullfile(outdir,'inv_120deg_spectrum.png'), 'Resolution', 130);

fprintf('  All checks passed. Figures in %s\n', outdir);
