% wind_fidelity_check.m
% Cross-validates the averaged model against the switched one.
%
% This is the check that earns the right to use the averaged model for
% controller tuning and the SCR sweep: if the two disagree, every result from
% the fast model is suspect.
%
% Method - the rotor is PINNED (inertia forced huge) at the rated operating
% point. Two reasons:
%   1. The rotor settles in ~5 s. The switched model runs at ~200x real time,
%      so a mechanically-settled switched run would take ~16 minutes.
%   2. Pinning isolates what the switched model is actually FOR: the rectifier
%      and converter. Any difference left is a converter-fidelity difference,
%      not a rotor transient.
% Energy accounting does not close while pinned (the infinite flywheel supplies
% whatever it is asked for) - that is expected, and is why the checks below are
% on the electrical operating point rather than on efficiency.
%
% Three defects were found this way, none visible in the averaged model:
%   - a duty feedforward that silently cancelled the current loop
%   - single-sample-per-period current sensing reading the ripple minimum
%     instead of the mean, biasing the current ~half the ripple high
%   - (30 kW rescale, 4 Sep) the boost diode left at Simscape's default 0.3 ohm:
%     7 W at 3 kW, 2.7 kW at 60 kW. Now wp.Ron_dev, shared by every device.
%
% Usage:
%   addpath(genpath('params'), genpath('scripts'), genpath('models'));
%   wind_fidelity_check
%
% Owner: Ba Huy Ta

clear; clc;
wp = windParams();

v_test = wp.v_rated;
w_mpp  = wp.lam_opt*v_test/wp.R;
% The comparison window is the last quarter of the run, and it has to sit
% after the stator's DC-offset transient has decayed - that takes ~6 Ls/Rs,
% which is 32 ms at 30 kW but 36 ms at 60 kW. A fixed 0.2 s run passed at
% 30 kW and failed at 60 kW (i_L -4%, P_dc -3%) for no reason but this, so
% the run length now follows the time constant. Minimum 2000 switching periods.
T_stop = max(0.2, 8*wp.Ls/wp.Rs);
t = (0:1e-4:T_stop)';
v = v_test*ones(size(t));

P_ref = wp.k_opt*w_mpp^3;           % torque-law power reference at this speed

% Seed every state at the pinned operating point - inductor current, rotor
% speed (an effectively infinite flywheel) and the rectifier capacitor. Left
% at 0 V, C_rect draws an inrush through the bridge whose DC offset in the
% stator is what the window above has to outlast. All scale with the rating,
% so none is a literal number.
ov = struct('w_init', w_mpp, 'iL_init', 0.8*P_ref/wp.V_rect_r, 'J', 1e4*wp.J, ...
            'V_rect_init', 1.35*(wp.p*w_mpp*wp.lam_pm)*sqrt(3)/sqrt(2));

fprintf('=== Averaged vs switched, rotor pinned at %.1f rad/s (%g m/s) ===\n', ...
        w_mpp, v_test);
fprintf('reference power from the torque law = %.0f W\n\n', P_ref);

M = struct();
for mm = {'windPlantSw','windPlantAvg'}
    mdl = mm{1};
    tic;
    [tl, logs] = windSim(t, v, struct('model',mdl, 'override',ov));
    el = toc;
    tail = @(ts) ts.Data(ts.Time >= 0.75*T_stop);
    gl   = @(n) tail(logs.get(n).Values);

    r.iL    = mean(gl('i_L'));
    r.Vr    = mean(gl('V_rect'));
    r.duty  = mean(tail(tl.duty));
    r.Pdc   = mean(tail(tl.P_dc));
    r.iLrip = max(gl('i_L')) - min(gl('i_L'));
    r.wall  = el;
    M.(matlab.lang.makeValidName(mdl)) = r;

    fprintf('%-14s  i_L %6.2f A   V_rect %6.1f V   duty %5.3f   P_dc %6.0f W   (%.0f s wall)\n', ...
            mdl, r.iL, r.Vr, r.duty, r.Pdc, r.wall);
end

s = M.windPlantSw; a = M.windPlantAvg;
pct = @(x,y) 100*(x-y)/abs(y);

fprintf('\n=== Agreement ===\n');
rows = {'i_L', s.iL, a.iL; 'V_rect', s.Vr, a.Vr; 'duty', s.duty, a.duty; 'P_dc', s.Pdc, a.Pdc};
for k = 1:size(rows,1)
    fprintf('  %-8s switched %9.2f   averaged %9.2f   %+6.2f%%\n', ...
            rows{k,1}, rows{k,2}, rows{k,3}, pct(rows{k,2}, rows{k,3}));
end

fprintf('\n=== What only the switched model shows ===\n');
fprintf('  inductor current ripple: %.2f A pk-pk (%.1f%% of mean)\n', ...
        s.iLrip, 100*s.iLrip/s.iL);
fprintf('  predicted V_rect*d/(L*f_sw) = %.2f A\n', s.Vr*s.duty/(wp.L_boost*wp.f_sw));
fprintf('  averaged model ripple:   %.4f A  (zero by construction)\n', a.iLrip);

%% ---- Checks ------------------------------------------------------------
fprintf('\n=== Checks ===\n');
R = {'i_L agrees within 3%',    abs(pct(s.iL,   a.iL))   < 3, sprintf('%+.2f%%', pct(s.iL,a.iL))
     'V_rect agrees within 3%', abs(pct(s.Vr,   a.Vr))   < 3, sprintf('%+.2f%%', pct(s.Vr,a.Vr))
     'duty agrees within 3%',   abs(pct(s.duty, a.duty)) < 3, sprintf('%+.2f%%', pct(s.duty,a.duty))
     'P_dc agrees within 3%',   abs(pct(s.Pdc,  a.Pdc))  < 3, sprintf('%+.2f%%', pct(s.Pdc,a.Pdc))
     'switched tracks its current reference', ...
                                abs(100*(s.iL - P_ref/s.Vr)/(P_ref/s.Vr)) < 3, ...
                                sprintf('%.2f vs ref %.2f A', s.iL, P_ref/s.Vr)};
npass = 0;
for k = 1:size(R,1)
    tag = 'FAIL';
    if R{k,2}, tag = 'PASS'; npass = npass + 1; end
    fprintf('  [%s] %-40s %s\n', tag, R{k,1}, R{k,3});
end
fprintf('\n  %d/%d checks passed\n', npass, size(R,1));
if npass < size(R,1)
    warning('wind_fidelity_check:failed', ...
            'averaged model does NOT match switched - do not trust averaged results');
end
