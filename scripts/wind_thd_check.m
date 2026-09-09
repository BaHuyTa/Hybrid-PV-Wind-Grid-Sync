% wind_thd_check.m
% The FFT / THD workflow (ILC goal G1), demonstrated on the switched wind model
% without Specialized Power Systems: log the Simscape network, take a whole
% number of electrical cycles, FFT, read the harmonics off the bins.
%
% Three spectra, each answering a question the spec leaves as words:
%   1. PMSG stator current. The 6-pulse bridge draws non-sinusoidal current;
%      spec section 1 calls that an "accepted limitation". This puts a number
%      on it: THD and the 5th/7th/11th/13th, the 6-pulse signature.
%   2. Current into the shared DC bus. What the inverter's DC-link loop actually
%      sees from the wind branch: the 6th-harmonic bridge ripple and the 10 kHz
%      switching ripple. Integration checks C_dc against this.
%   3. Boost inductor current. The switching ripple the averaged model cannot
%      show, at the frequency and magnitude the sizing predicts.
%
% Rotor pinned at the rated operating point, as in wind_fidelity_check, so the
% electrical frequency is constant across the FFT window.
%
% Output: results/thd_spectra.png (gitignored - regenerate, don't commit)
%
% Usage:
%   addpath(genpath('params'), genpath('scripts'), genpath('models'));
%   wind_thd_check
%
% Owner: Ba Huy Ta

clear; clc;
wp = windParams();

w_mpp  = wp.lam_opt*wp.v_rated/wp.R;
f_e    = wp.p*w_mpp/(2*pi);                    % electrical frequency at rated
n_cyc  = 8;                                    % whole cycles in the FFT window
T_settle = max(0.20, 7*wp.Ls/wp.Rs);           % > 6 stator time constants at any rating (Ls/Rs = 36 ms at 60 kW)
T_stop = T_settle + n_cyc/f_e;                 % settle, then the window
t = (0:1e-4:T_stop)';  v = wp.v_rated*ones(size(t));
P_ref = wp.k_opt*w_mpp^3;
% Start every state at the pinned operating point, including the rectifier
% capacitor: left at 0 V it draws an inrush through the bridge whose DC
% offset in the stator takes ~200 ms to decay and poisons the spectrum.
ov = struct('w_init', w_mpp, 'iL_init', 0.8*P_ref/wp.V_rect_r, 'J', 1e4*wp.J, ...
            'V_rect_init', 1.35*(wp.p*w_mpp*wp.lam_pm)*sqrt(3)/sqrt(2));

fprintf('=== FFT / THD on windPlantSw, rotor pinned at %.1f rad/s (f_e = %.1f Hz) ===\n', w_mpp, f_e);
tic;
[~, logs, out] = windSim(t, v, struct('model','windPlantSw', 'override',ov, 'simscape_log',true));
fprintf('simulated %.2f s in %.0f s wall; FFT window %.4f s = %d cycles at %.1f Hz, resampled at %g us\n\n', T_stop, toc, n_cyc/f_e, n_cyc, f_e, wp.Ts_power*1e6);

sl  = out.simlog.PowerStage;
sig = struct( ...
    'name', {'PMSG stator current i_a', 'current into DC bus', 'boost inductor current'}, ...
    'ts',   {sl.PMSG.i_a.series, sl.sense_idc.I.series, sl.L_boost.i.series});

%% ---- FFT over the last n_cyc whole electrical cycles --------------------
T_w = n_cyc/f_e;
f   = figure('Color','w','Position',[100 100 1400 900]);
tiledlayout(f, 3, 1, 'TileSpacing','compact', 'Padding','compact');
R = struct();
for k = 1:numel(sig)
    tt = sig(k).ts.time;  x = sig(k).ts.values;
    % The Simscape log is NOT uniformly sampled: it adds a point at every
    % diode/IGBT switching event. An FFT assumes a fixed sample interval, so
    % resample onto the solver step over the last n_cyc whole cycles - that
    % puts every harmonic exactly on a bin.
    [tt, iu] = unique(tt);  x = x(iu);
    Ts = wp.Ts_power;
    N  = round(T_w/Ts) + 1;
    tu = tt(end) - (N-1:-1:0)'*Ts;              % ends exactly on the last logged sample
    assert(tt(1) <= tu(1), 'Simscape log covers %.3f s but the FFT window needs %.3f s - is SimscapeLogLimitData off?', tt(end)-tt(1), T_w);
    x  = interp1(tt, x, tu, 'linear');  tt = tu;
    X  = fft(x)/N;  X(2:end) = 2*X(2:end);      % single-sided amplitude
    fr = (0:N-1)'/(N*Ts);
    nh = floor(N/2);  X = abs(X(1:nh));  fr = fr(1:nh);
    bin = @(fq) X(1 + round(fq*N*Ts));          % amplitude at frequency fq (nearest bin)

    r.dc   = X(1);
    r.pp   = max(x) - min(x);                   % time-domain pk-pk, for the ripple cross-check
    win    = fr > 0.5*f_e & fr < 1.5*f_e;       % where the fundamental should be
    [~, i1] = max(X(win)); f1s = fr(win); r.f1 = f1s(i1);   % measured, not assumed
    r.I1   = bin(f_e);
    hs     = 2:50;                Ih = arrayfun(@(h) bin(h*f_e), hs);
    r.thd  = 100*sqrt(sum(Ih.^2))/r.I1;
    r.h3   = 100*bin(3*f_e)/r.I1;
    r.h5   = 100*bin(5*f_e)/r.I1;  r.h7 = 100*bin(7*f_e)/r.I1;
    r.h11  = 100*bin(11*f_e)/r.I1; r.h13 = 100*bin(13*f_e)/r.I1;
    r.h6   = bin(6*f_e);                                   % DC-side bridge ripple
    [~, i_sw] = max(X(fr > 0.5*wp.f_sw & fr < 1.5*wp.f_sw)); fsub = fr(fr > 0.5*wp.f_sw & fr < 1.5*wp.f_sw);
    r.f_sw_meas = fsub(i_sw);  r.I_sw = bin(r.f_sw_meas);
    R.(matlab.lang.makeValidName(sig(k).name)) = r;

    ax = nexttile; semilogy(fr, X, 'LineWidth', 1); grid on; xlim([0 2*wp.f_sw]);
    ylabel('A'); title(sprintf('%s   (DC %.1f A, fundamental %.1f A at %.0f Hz)', sig(k).name, r.dc, r.I1, r.f1));
    hold on; xline(wp.f_sw, '--', sprintf('f_{sw} = %g kHz', wp.f_sw/1e3)); xline(6*f_e, ':', '6 f_e');
end
xlabel('frequency (Hz)');
outDir = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'results');
if ~exist(outDir, 'dir'), mkdir(outDir); end
exportgraphics(f, fullfile(outDir, 'thd_spectra.png'), 'Resolution', 130);

%% ---- Report -------------------------------------------------------------
s = R.PMSGStatorCurrentI_a;  d = R.currentIntoDCBus;  l = R.boostInductorCurrent;
fprintf('Stator current:  fundamental %.1f A at %.1f Hz | THD %.1f%% | 3rd %.1f%%  5th %.1f%%  7th %.1f%%  11th %.1f%%  13th %.1f%%\n', ...
        s.I1, s.f1, s.thd, s.h3, s.h5, s.h7, s.h11, s.h13);
if s.thd > 60
    fprintf('                 THD above 60%%: capacitor-input regime. C_rect (%.0f uF) sits straight after the\n', wp.C_rect*1e6);
    fprintf('                 bridge, so the stator charges it in short pulses each half cycle. The inductive-input\n');
    fprintf('                 textbook figure (~31%%) would need the boost inductor on the bridge side of C_rect.\n');
else
    fprintf('                 Below the ideal stiff-source 6-pulse figure (~31%%): the stator reactance (Xs ~ 0.22 pu)\n');
    fprintf('                 gives a long commutation overlap that rounds the 120-degree current blocks. This is the\n');
    fprintf('                 "accepted limitation" of spec section 1, quantified.\n');
end
C_dc = 44e-3;   % F, the shared bus capacitor: TestHarness/config/harnessParams.m, P.plant.C
fprintf('DC bus in:       mean %.1f A | 6 f_e ripple %.2f A | switching ripple %.2f A at %.0f Hz\n', ...
        d.dc, d.h6, d.I_sw, d.f_sw_meas);
fprintf('                 (the boost diode conducts in pulses, so that 10 kHz component is what C_dc absorbs:\n');
fprintf('                  with C_dc = %.0f mF it is %.3f V of ripple; integration checks C_dc against this)\n', C_dc*1e3, d.I_sw/(2*pi*d.f_sw_meas*C_dc));
fprintf('Inductor:        mean %.1f A | switching ripple %.2f A at %.0f Hz (predicted pk-pk %.1f A -> amplitude ~%.1f A)\n', ...
        l.dc, l.I_sw, l.f_sw_meas, 0.52*340/(wp.L_boost*wp.f_sw), 0.52*340/(wp.L_boost*wp.f_sw)/2);

%% ---- Checks ------------------------------------------------------------
fprintf('\n=== Checks ===\n');
I_tri = (8/pi^2)*l.pp/2;                 % 10 kHz amplitude a triangle wave of that pk-pk would have
C = {'window is settled: stator DC < 3% of fundamental', s.dc < 0.03*s.I1,                               sprintf('DC %.2f A, fundamental %.1f A', s.dc, s.I1)
     'stator fundamental within 2% of p*w/(2 pi)',   abs(s.f1 - f_e) < 0.02*f_e,                        sprintf('%.1f Hz vs %.1f Hz', s.f1, f_e)
     'no triplen harmonics (three-wire machine)',     s.h3 < 5,                                          sprintf('3rd = %.1f%%', s.h3)
     '6-pulse signature: 5th > 7th > 11th > 13th',    s.h5 > s.h7 && s.h7 > s.h11 && s.h11 > s.h13,      sprintf('%.1f > %.1f > %.1f > %.1f %%', s.h5, s.h7, s.h11, s.h13)
     'inductor 10 kHz component matches its pk-pk',   abs(l.f_sw_meas - wp.f_sw) < 2/T_w && abs(l.I_sw - I_tri) < 0.3*I_tri, ...
                                                      sprintf('%.1f A at %.0f Hz vs %.1f A from %.1f A pk-pk', l.I_sw, l.f_sw_meas, I_tri, l.pp)
     'bridge ripple does not reach the DC bus (< 10%)', d.h6 < 0.10*d.dc,                                 sprintf('6 f_e: %.2f A of %.1f A mean', d.h6, d.dc)};
npass = 0;
for k = 1:size(C,1)
    tag = 'FAIL'; if C{k,2}, tag = 'PASS'; npass = npass + 1; end
    fprintf('  [%s] %-44s %s\n', tag, C{k,1}, C{k,3});
end
fprintf('\n  %d/%d checks passed\n', npass, size(C,1));
