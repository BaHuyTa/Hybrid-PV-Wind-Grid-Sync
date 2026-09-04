% wind_mppt_sweep.m
% Tunes and justifies the P&O MPPT settings in params/windParams.m.
%
% Every run here forces wp.mppt_mode = 0. The default is now torque control
% (mode 1), which does not use the duty seed or the perturbation settings, so
% without the override this script would measure the torque controller 35 times
% and call it a sweep. (It did exactly that after the default changed - fixed
% during the 30 kW rescale, 4 Sep 2026.)
%
% Two questions, in order:
%   1. What can the plant actually deliver? An open-loop duty sweep gives the
%      true power-vs-duty curve and its peak. Without this number there is
%      nothing to measure the tracker against - "98% of available wind power"
%      is not achievable, because the rectifier and boost take their cut first.
%   2. How close does P&O get, and over what range of settings is that stable?
%
% The headline result: the perturbation period must be LONGER than the rotor
% settling time (4.78 s). Perturb faster and P&O measures the rotor's transient
% instead of the new steady state, and walks the wrong way.
%
% Usage:
%   addpath(genpath('params'), genpath('scripts'), genpath('models'));
%   wind_mppt_sweep
%
% Owner: Ba Huy Ta

clear; clc;
wp = windParams();

v_test = 12;                       % rated wind
T      = 150;                      % long enough for the rotor to settle
t      = (0:0.05:T)';
v      = v_test*ones(size(t));
P_avail = 0.5*wp.rho*wp.A*wp.Cp_max*v_test^3;

%% ---- 1. Open-loop duty sweep: what is actually achievable? ------------
fprintf('=== 1. Open-loop duty sweep at %g m/s ===\n', v_test);
fprintf('  %-7s %-8s %-8s %-11s %-9s\n', 'duty', 'lambda', 'Cp', 'P_mech[W]', 'P_dc[W]');

D = 0.30:0.025:0.75;
P_ol = zeros(size(D));
for k = 1:numel(D)
    % mppt_mode is forced to 0 (P&O) with a zero step, i.e. a fixed duty. Without
    % that, the default torque controller (mode 1) ignores d_init and every
    % point of the "sweep" lands on the same operating point.
    o = struct('override', struct('mppt_mode',0, 'dD',0, 'd_init',D(k), 'd_min',0.01));
    tl = windSim(t, v, o);
    P_ol(k) = tailmean(tl.P_dc, T-10);
    fprintf('  %-7.3f %-8.2f %-8.3f %-11.0f %-9.0f\n', D(k), ...
        tailmean(tl.lambda,T-10), tailmean(tl.Cp,T-10), ...
        tailmean(tl.P_mech,T-10), P_ol(k));
end

[P_ach, ib] = max(P_ol);
d_ach = D(ib);
fprintf('\n  achievable  = %.0f W at duty %.3f\n', P_ach, d_ach);
fprintf('  wind avail  = %.0f W  ->  conversion %.1f%%\n', P_avail, 100*P_ach/P_avail);
fprintf('  (the gap is the rectifier and boost losses, not a tracking error)\n\n');

assert(abs(tailmean(tl.lambda,T-10)) > 0, 'sweep produced no data');

%% ---- 2. P&O settings sweep --------------------------------------------
% Measured against P_ach, not against the wind - a tracker cannot beat the
% converter chain in front of it.
fprintf('=== 2. P&O tracking efficiency vs (Ts_mppt, dD) ===\n');
fprintf('  mean P_dc over the last third of a %g s run, as %% of %.0f W\n\n', T, P_ach);

Ts_list = [0.5 1 2 5];
dD_list = [0.002 0.005 0.010 0.020];

fprintf('  %-9s', 'dD \ Ts');
for j = 1:numel(Ts_list)
    fprintf('%8gs', Ts_list(j));
end
fprintf('\n');

eff = zeros(numel(dD_list), numel(Ts_list));
for i = 1:numel(dD_list)
    fprintf('  %-9.3f', dD_list(i));
    for j = 1:numel(Ts_list)
        o = struct('override', struct('mppt_mode',0, 'Ts_mppt',Ts_list(j), 'dD',dD_list(i)));
        tl = windSim(t, v, o);
        eff(i,j) = 100*tailmean(tl.P_dc, 2*T/3)/P_ach;
        fprintf('%8.1f%%', eff(i,j));
    end
    fprintf('\n');
end

%% ---- 3. The chosen operating point ------------------------------------
i_sel = find(dD_list == wp.dD, 1);
j_sel = find(Ts_list == wp.Ts_mppt, 1);
fprintf('\n=== 3. Selected: Ts_mppt = %g s, dD = %g ===\n', wp.Ts_mppt, wp.dD);
if ~isempty(i_sel) && ~isempty(j_sel)
    fprintf('  tracking efficiency = %.1f%%\n', eff(i_sel,j_sel));
    assert(eff(i_sel,j_sel) > 95, ...
        'Selected MPPT settings track below 95%% - retune before shipping');

    % Chosen for the neighbourhood, not just the peak: a setting that is good
    % only at its exact value will not survive the plant changing slightly.
    ii = max(1,i_sel-1):min(numel(dD_list),i_sel+1);
    jj = max(1,j_sel-1):min(numel(Ts_list),j_sel+1);
    fprintf('  worst neighbour     = %.1f%%\n', min(min(eff(ii,jj))));
end

fprintf('\n  Ts_mppt must exceed the %.2f s rotor settling time - see\n', 4.78);
fprintf('  wind_model_check.m section 4 for where that number comes from.\n');

% -------------------------------------------------------------------------
function m = tailmean(ts, t_from)
% Mean over the settled tail of a run.
m = mean(ts.Data(ts.Time >= t_from));
end
