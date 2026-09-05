function wp = windParams()
% WINDPARAMS  Single source of truth for the wind subsystem.
%
% Both the averaged and switched Simulink models read from here. Never hard-code
% a value into a block mask — change it here so the two models can't drift apart.
%
% Owner: Ba Huy Ta (wind plant, W5-W6)
% Verified by scripts/wind_model_check.m
%
%   wp = windParams();

%% ---- Design assumptions (the only free choices) -----------------------
wp.P_elec   = 60000;    % W    rated electrical output (Option B site scale, 5 Sep 2026)
wp.v_rated  = 12;       % m/s  ASSUMPTION - not from proposal, see README
wp.v_cutin  = 4;        % m/s  ASSUMPTION - set by max boost duty 0.85
wp.eta      = 0.90;     % -    source-to-DC-link efficiency
wp.rho      = 1.225;    % kg/m^3
wp.p        = 10;       % -    pole pairs (direct drive)
wp.H        = 3;        % s    inertia constant
wp.V_rect_r = 400;      % V    target rectified voltage at rated wind

%% ---- Shared with the rest of the team ---------------------------------
wp.V_dc     = 700;      % V    shared DC link (owned by integration)
wp.duty_max = 0.85;     % -    boost duty ceiling

%% ---- Cp(lambda,beta), Heier coefficient set ---------------------------
wp.cp_c = [0.5176, 116, 0.4, 5, 21, 0.0068];
wp.beta = 0;            % deg  fixed pitch (stall-regulated, no pitch control)

% NOTE: the standard form defines the RECIPROCAL 1/lambda_i. c2/lambda_i is
% therefore c2 * li_inv, NOT c2 / li_inv. Getting this backwards flattens the
% curve and pushes the peak to lambda ~ 0.
wp.li_inv = @(lam,beta) 1./(lam+0.08*beta) - 0.035./(beta.^3+1);
wp.Cp     = @(lam,beta) wp.cp_c(1) * ...
            (wp.cp_c(2)*wp.li_inv(lam,beta) - wp.cp_c(3)*beta - wp.cp_c(4)) ...
            .* exp(-wp.cp_c(5)*wp.li_inv(lam,beta)) + wp.cp_c(6)*lam;

%% ---- Derived (do not edit - change the assumptions above) -------------
lam = linspace(0.1, 15, 20000);
[wp.Cp_max, i] = max(wp.Cp(lam, wp.beta));
wp.lam_opt = lam(i);                                    % 0.4800 @ 8.100

wp.P_mech  = wp.P_elec/wp.eta;                          % 66667 W
wp.A       = 2*wp.P_mech/(wp.rho*wp.Cp_max*wp.v_rated^3);
wp.R       = sqrt(wp.A/pi);                             % 6.463 m
wp.w_rated = wp.lam_opt*wp.v_rated/wp.R;                % 15.04 rad/s (144 rpm)
wp.f_e     = wp.p*wp.w_rated/(2*pi);                    % 23.9 Hz

% PMSG: flux linkage set so the 6-pulse bridge gives V_rect_r at rated speed
wp.V_ll    = wp.V_rect_r/1.35;                          % 6-pulse: Vdc = 1.35*Vll
wp.lam_pm  = (wp.V_ll*sqrt(2)/sqrt(3))/(wp.p*wp.w_rated);   % 1.609 Wb
wp.J       = 2*wp.H*wp.P_mech/wp.w_rated^2;             % 1768 kg.m^2

% Optimal torque coefficient, T = k*w^2 (fallback MPPT if P&O hunts)
wp.k_opt   = 0.5*wp.rho*pi*wp.R^5*wp.Cp_max/wp.lam_opt^3;

%% ---- Machine electricals (placeholder - refine in W5) -----------------
wp.Rs = 0.025;          % ohm   stator resistance
wp.Ls = 0.4e-3;         % H     stator inductance (Ld = Lq, round rotor)

%% ---- Converter + sample times -----------------------------------------
wp.f_sw     = 10e3;     % Hz   boost switching frequency
wp.L_boost  = 0.25e-3;  % H    boost inductor
wp.Ts_power = 1e-6;     % s    switched-model solver step
wp.Ts_ctrl  = 1/wp.f_sw;% s    boost current loop
wp.Ts_mppt  = 0.1;      % s    P&O perturbation period (slow - rotor inertia)

% NOTE: the DC-link capacitor is NOT defined here. It lives in the integration
% model and is owned by Hoang. Exactly one place owns C_dc.
end
