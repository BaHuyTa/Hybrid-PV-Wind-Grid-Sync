% wind_scenarios.m
% Scenario test harness for the wind branch (docs/wind-model-spec.md section 6).
%
% Runs the averaged model through the operating cases the subsystem has to
% survive, in BOTH MPPT modes, and applies pass/fail checks to the configured
% default. Every threshold below is a number someone can argue with - that is
% deliberate. A check that cannot fail is not a test.
%
% Tracking efficiency is measured against what the PLANT can deliver, not
% against the wind: the rectifier and boost take ~4.4% before the tracker sees
% anything, so "% of wind available" would understate the tracker forever.
% eta_conv is that conversion factor, measured by wind_mppt_sweep.m.
%
% Usage:
%   addpath(genpath('params'), genpath('scripts'), genpath('models'));
%   wind_scenarios
%
% Owner: Ba Huy Ta

clear; clc;
wp = windParams();

eta_conv = 0.956;                                   % plant conversion at the MPP
Pach     = @(v) eta_conv*0.5*wp.rho*wp.A*wp.Cp_max*v.^3;

modes      = [0 1];
mode_names = {'P&O', 'torque'};

%% ---- Scenario definitions ---------------------------------------------
S = struct('name',{},'t',{},'v',{},'en',{},'note',{});

t = (0:0.05:150)';
S(end+1) = mk('S1 steady rated', t, wp.v_rated*ones(size(t)), 1, ...
              'baseline: can it find the peak and stay there');

t = (0:0.05:200)';  v = 8*ones(size(t)); v(t>=60) = 12;
S(end+1) = mk('S2 step 8->12', t, v, 1, 'the bandwidth-separation scenario');

t = (0:0.05:300)';  v = min(max(4 + 8*(t-30)/180, 4), 12);
S(end+1) = mk('S3 ramp 4->12', t, v, 1, 'sustained change - where P&O fails');

t = (0:0.05:200)';  v0=10; Vg=5; Tg=10.5; t0=80;    % IEC 61400 "Mexican hat"
v = v0*ones(size(t)); g = t>=t0 & t<=t0+Tg; tg = t(g)-t0;
v(g) = v0 - 0.37*Vg*sin(3*pi*tg/Tg).*(1-cos(2*pi*tg/Tg));
S(end+1) = mk('S4 extreme gust', t, v, 1, 'IEC extreme operating gust');

t = (0:0.05:300)';  v = 3*ones(size(t)); v(t>=60 & t<200) = 6;
en = ones(size(t)); en(t>=250) = 0;
S(end+1) = mk('S5 cut-in/cut-out', t, v, en, 'and the enable line dropping');

t = (0:0.05:300)';  vm = 9;
v = vm + 1.2*sin(2*pi*t/37) + 0.8*sin(2*pi*t/13 + 1.1) ...
       + 0.5*sin(2*pi*t/7.3 + 2.4) + 0.3*sin(2*pi*t/3.1 + 0.7);
S(end+1) = mk('S6 turbulent', t, v, 1, 'sum of sines about a mean');

%% ---- Run every scenario in both modes ---------------------------------
fprintf('=== Wind branch scenario harness ===\n');
fprintf('model windPlantAvg | default mppt_mode = %d (%s)\n', ...
        wp.mppt_mode, mode_names{wp.mppt_mode+1});
fprintf('P&O: Ts_mppt = %g s, dD = %g | torque: f_i_bw = %g Hz\n\n', ...
        wp.Ts_mppt, wp.dD, wp.f_i_bw);

M = struct();                                   % M(scenario, mode) metrics
for is = 1:numel(S)
    for im = 1:numel(modes)
        tl = windSim(S(is).t, S(is).v, ...
                     struct('enable', S(is).en, ...
                            'override', struct('mppt_mode', modes(im))));
        M(is,im).tl  = tl;
        tt  = tl.P_dc.Time;
        vq  = interp1(S(is).t, S(is).v, tt);
        % Settled window: skip the first fifth, which is the rotor starting
        % from its initial condition rather than anything the tracker did.
        msk = tt >= 0.2*tt(end);
        % Energy capture: ratio of MEANS, not mean of ratios. The mean of the
        % instantaneous ratio is meaningless here - it divides by an available
        % power that goes to nearly zero in a lull and reports >100%.
        M(is,im).eff   = 100*mean(tl.P_dc.Data(msk))/mean(Pach(vq(msk)));
        M(is,im).P     = mean(tl.P_dc.Data(tt >= 0.8*tt(end)));
        M(is,im).d_max = max(tl.duty.Data);
        M(is,im).w_max = max(tl.omega_m.Data);
        M(is,im).P_min = min(tl.P_dc.Data);
        M(is,im).lam   = mean(tl.lambda.Data(tl.lambda.Time >= 0.8*tt(end)));
    end
end

%% ---- Mode comparison ---------------------------------------------------
fprintf('=== Tracking efficiency by MPPT mode ===\n');
fprintf('  %-20s %10s %10s   %s\n', 'scenario', mode_names{1}, mode_names{2}, 'note');
for is = 1:numel(S)
    fprintf('  %-20s %9.1f%% %9.1f%%   %s\n', S(is).name, ...
            M(is,1).eff, M(is,2).eff, S(is).note);
end

%% ---- Checks, against the configured default ---------------------------
im = find(modes == wp.mppt_mode, 1);
R = {};
add = @(n,c,d) {n, logical(c), d};

R(end+1,:) = add('S1 tracking >= 95%',        M(1,im).eff >= 95,   sprintf('%.1f%%', M(1,im).eff));
R(end+1,:) = add('S1 delivers >= P_elec',     M(1,im).P >= wp.P_elec, sprintf('%.0f >= %.0f W', M(1,im).P, wp.P_elec));
R(end+1,:) = add('S2 step tracking >= 90%',   M(2,im).eff >= 90,   sprintf('%.1f%%', M(2,im).eff));
R(end+1,:) = add('S3 ramp tracking >= 90%',   M(3,im).eff >= 90,   sprintf('%.1f%%', M(3,im).eff));
R(end+1,:) = add('S4 no rotor overspeed',     M(4,im).w_max < 1.25*wp.w_rated, ...
                 sprintf('%.1f < %.1f rad/s', M(4,im).w_max, 1.25*wp.w_rated));
R(end+1,:) = add('S5 zero power when disabled', ...
                 max(abs(M(5,im).tl.P_dc.Data(M(5,im).tl.P_dc.Time>=260))) < 1e-6, ...
                 sprintf('%.1e W', max(abs(M(5,im).tl.P_dc.Data(M(5,im).tl.P_dc.Time>=260)))));
R(end+1,:) = add('S6 turbulent tracking >= 90%', M(6,im).eff >= 90, sprintf('%.1f%%', M(6,im).eff));

% Duty headroom is only claimed BETWEEN cut-in and rated. S5 deliberately runs
% at 3 m/s, below cut-in, where the boost is supposed to saturate - including it
% here would test a claim the spec never made.
in_range = [1 2 3 4 6];
d_all = max(arrayfun(@(k) M(k,im).d_max, in_range));
P_all = min(arrayfun(@(k) M(k,im).P_min, 1:numel(S)));
R(end+1,:) = add('duty < duty_max, cut-in..rated', d_all < wp.duty_max, ...
                 sprintf('%.3f < %.2f', d_all, wp.duty_max));
R(end+1,:) = add('S5 saturates gracefully below cut-in', ...
                 M(5,im).d_max <= wp.duty_max + 1e-9 && M(5,im).P_min >= -1e-6, ...
                 sprintf('duty capped at %.3f, no reverse power', M(5,im).d_max));
R(end+1,:) = add('no negative export, all scenarios', P_all >= -1e-6, ...
                 sprintf('%.1e W', P_all));

fprintf('\n=== Checks (mppt_mode = %d, %s) ===\n', wp.mppt_mode, mode_names{im});
npass = 0;
for k = 1:size(R,1)
    tag = 'FAIL';
    if R{k,2}, tag = 'PASS'; npass = npass + 1; end
    fprintf('  [%s] %-36s %s\n', tag, R{k,1}, R{k,3});
end
fprintf('\n  %d/%d checks passed\n', npass, size(R,1));
if npass < size(R,1)
    warning('wind_scenarios:failed', '%d check(s) failed', size(R,1)-npass);
end

% -------------------------------------------------------------------------
function s = mk(name, t, v, en, note)
if isscalar(en), en = en*ones(size(t)); end
s = struct('name',name, 't',t, 'v',v, 'en',en, 'note',note);
end
