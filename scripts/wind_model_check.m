% wind_model_check.m
% Verifies the wind subsystem sizing in docs/wind-model-spec.md.
%
% Reads every constant from params/windParams.m so this script and the Simulink
% models can never disagree. Plain MATLAB - no toolbox needed, so anyone on the
% team can run it.
%
% Checks:
%   1. Cp(lambda,beta) peak and lambda_opt
%   2. Rotor sizing for wp.P_elec (30 kW) electrical at rated wind
%   3. Boost duty across the operating range (must stay under duty_max)
%   4. Rotor mechanical settling time - the number the control pair needs
%
% Usage:
%   addpath(genpath('params'), genpath('scripts'));
%   wind_model_check

clear; clc;
wp = windParams();

%% ---- 1. Cp curve ------------------------------------------------------
fprintf('=== 1. Cp curve (beta = %g) ===\n', wp.beta);
fprintf('  Cp_max   = %.4f\n', wp.Cp_max);
fprintf('  lam_opt  = %.3f\n\n', wp.lam_opt);

assert(wp.Cp_max > 0.4 && wp.Cp_max < 0.6, 'Cp_max outside physical range');
assert(wp.lam_opt > 1 && wp.lam_opt < 14, ...
       'lam_opt at grid boundary - check the 1/lambda_i reciprocal');

%% ---- 2. Rotor sizing --------------------------------------------------
fprintf('=== 2. Rotor sizing for %.0f W elec at %.0f m/s ===\n', ...
        wp.P_elec, wp.v_rated);
fprintf('  P_mech   = %.0f W\n', wp.P_mech);
fprintf('  Area     = %.2f m^2  ->  R = %.3f m  (D = %.2f m)\n', ...
        wp.A, wp.R, 2*wp.R);
fprintf('  w_rated  = %.1f rad/s = %.0f rpm\n', ...
        wp.w_rated, wp.w_rated*60/(2*pi));
fprintf('  f_elec   = %.1f Hz  (p = %d)\n', wp.f_e, wp.p);
fprintf('  V_ll     = %.0f V rms  ->  lam_pm = %.3f Wb\n', wp.V_ll, wp.lam_pm);
fprintf('  J        = %.2f kg.m^2  (H = %.1f s)\n\n', wp.J, wp.H);

%% ---- 3. Duty ratio across operating range -----------------------------
fprintf('=== 3. Boost duty vs wind speed (at MPPT) ===\n');
fprintf('  %-8s %-10s %-10s %-10s %-8s\n', ...
        'v[m/s]', 'w[rad/s]', 'Vrect[V]', 'Pdc[W]', 'duty');

v_sweep  = wp.v_cutin:1:wp.v_rated+1;
duty_all = zeros(size(v_sweep));

for k = 1:numel(v_sweep)
    v  = v_sweep(k);
    w  = wp.lam_opt*v/wp.R;                          % MPPT holds lambda = lam_opt
    Vr = 1.35*(wp.p*w*wp.lam_pm)*sqrt(3)/sqrt(2);    % V_pk -> V_ll rms -> V_dc
    Pm = 0.5*wp.rho*wp.A*wp.Cp_max*v^3;
    duty_all(k) = 1 - Vr/wp.V_dc;
    fprintf('  %-8.1f %-10.1f %-10.0f %-10.0f %-8.3f\n', ...
            v, w, Vr, Pm*wp.eta, duty_all(k));
end

fprintf('\n  max duty = %.3f (limit %.2f)\n\n', max(duty_all), wp.duty_max);
assert(max(duty_all) < wp.duty_max, ...
       'Boost saturates at cut-in - raise v_cutin or lower V_rect target');

%% ---- 4. Rotor settling time -------------------------------------------
% Single mass, ideal optimal-torque control T = k*w^2 (best case; P&O is
% slower). Step wind 8 -> 12 m/s, measure time to 95% of the new w_opt.
v1 = 8; v2 = wp.v_rated;
w  = wp.lam_opt*v1/wp.R;
w_final = wp.lam_opt*v2/wp.R;

dt = 1e-3; t = 0; t_settle = NaN;
while t < 60
    lam_i  = w*wp.R/v2;
    T_aero = 0.5*wp.rho*wp.A*wp.Cp(lam_i, wp.beta)*v2^3/w;
    T_gen  = wp.k_opt*w^2;
    w = w + dt*(T_aero - T_gen)/wp.J;
    t = t + dt;
    if isnan(t_settle) && w >= 0.95*w_final
        t_settle = t;
    end
end

fprintf('=== 4. Mechanical response, wind step %g -> %g m/s ===\n', v1, v2);
fprintf('  w: %.1f -> %.1f rad/s\n', wp.lam_opt*v1/wp.R, w_final);
fprintf('  95%% settling = %.2f s   (ideal torque control)\n\n', t_settle);
fprintf('  Against the graded specs:\n');
fprintf('    inner current loop settling   0.002 s\n');
fprintf('    DC-link voltage recovery      0.200 s\n');
fprintf('    rotor mechanical settling     %.2f s  <- %.0fx slower\n', ...
        t_settle, t_settle/0.2);
fprintf('\n  All checks passed.\n');
