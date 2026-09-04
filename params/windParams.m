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
wp.P_elec   = 3000;     % W    rated electrical output (from proposal)
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

wp.P_mech  = wp.P_elec/wp.eta;                          % 3333 W
wp.A       = 2*wp.P_mech/(wp.rho*wp.Cp_max*wp.v_rated^3);
wp.R       = sqrt(wp.A/pi);                             % 1.445 m
wp.w_rated = wp.lam_opt*wp.v_rated/wp.R;                % 67.3 rad/s (642 rpm)
wp.f_e     = wp.p*wp.w_rated/(2*pi);                    % 107 Hz

% PMSG: flux linkage set so the 6-pulse bridge gives V_rect_r at rated speed
wp.V_ll    = wp.V_rect_r/1.35;                          % 6-pulse: Vdc = 1.35*Vll
wp.lam_pm  = (wp.V_ll*sqrt(2)/sqrt(3))/(wp.p*wp.w_rated);   % 0.360 Wb
wp.J       = 2*wp.H*wp.P_mech/wp.w_rated^2;             % 4.42 kg.m^2

% Optimal torque coefficient, T = k*w^2 (fallback MPPT if P&O hunts)
wp.k_opt   = 0.5*wp.rho*pi*wp.R^5*wp.Cp_max/wp.lam_opt^3;

%% ---- Machine electricals (placeholder - refine in W5) -----------------
wp.Rs = 0.5;            % ohm   stator resistance
wp.Ls = 8e-3;           % H     stator inductance (Ld = Lq, round rotor)

%% ---- Converter + sample times -----------------------------------------
wp.f_sw     = 10e3;     % Hz   boost switching frequency
wp.L_boost  = 5e-3;     % H    boost inductor
wp.Ts_power = 1e-6;     % s    switched-model solver step
wp.Ts_ctrl  = 1/wp.f_sw;% s    boost current loop
wp.Ts_mppt  = 5.0;      % s    P&O perturbation period - see note below

% Switched model only: the rectifier-side smoothing capacitor and the per-device
% diode drop. wp.V_f above is the drop across the TWO devices conducting in the
% bridge at any instant; the switched model needs the single-device value.
wp.C_rect   = 100e-6;   % F    rectifier-side smoothing capacitor (small)
wp.Vf_dev   = 0.8;      % V    forward drop of one diode

% NOTE: the DC-link capacitor is NOT defined here. It lives in the integration
% model and is owned by Hoang. Exactly one place owns C_dc.

%% ---- Loss + parasitic terms (needed by the Simulink models) -----------
% Small but not optional: without them the averaged boost has no damping and
% the rectifier looks like an ideal source, which flatters the MPPT result.
wp.B      = 0.01*(wp.P_mech/wp.w_rated)/wp.w_rated;  % N.m.s viscous damping
                                                     % (1% of rated torque at rated speed)
wp.R_L    = 0.10;       % ohm  boost inductor ESR
wp.V_f    = 1.6;        % V    diode bridge forward drop (2 devices conducting)

%% ---- Model initial conditions -----------------------------------------
% Start at the 8 m/s operating point: that is the initial condition of the
% 8 -> 12 m/s step scenario, so the model starts settled instead of spending
% the first seconds of every run spinning up from rest.
wp.v_init  = 8;                                   % m/s
wp.w_init  = wp.lam_opt*wp.v_init/wp.R;           % rad/s  = 44.9
wp.iL_init = 0;                                   % A

% Rectified voltage at the initial operating point, used to seed the duty so
% the boost does not slam the bus at t = 0.
wp.V_rect_init = 1.35*(wp.p*wp.w_init*wp.lam_pm)*sqrt(3)/sqrt(2);
wp.d_init      = 1 - wp.V_rect_init/wp.V_dc;

%% ---- P&O MPPT tuning ---------------------------------------------------
% MEASURED, not assumed. Ts_mppt must be LONGER than the rotor settling time
% (4.78 s), or P&O reads the rotor's transient instead of the new steady state
% and walks the wrong way. Tracking efficiency at 12 m/s, against the 3187 W
% the plant can actually deliver (open-loop duty sweep, scripts/wind_mppt_sweep.m):
%
%   Ts_mppt:     0.5 s    1 s     2 s     5 s
%   dD = 0.002   97.7%   97.6%   93.5%   94.3%
%   dD = 0.005   56.2%   94.6%   98.5%   99.0%   <- chosen
%   dD = 0.010   91.1%   55.4%   94.8%   97.9%
%   dD = 0.020   73.7%   91.4%   31.1%   89.6%
%
% The 31-56% cells are the hunting failure the spec flagged as a risk - it is
% real, and it is roughly what the original 0.1 s perturbation period gave.
% 5 s / 0.005 was chosen for its neighbourhood, not just its peak: the worst
% adjacent setting is still 93.5%, so it survives the plant changing slightly.
wp.dD      = 0.005;     % -    duty perturbation step
wp.d_min   = 0.05;      % -    duty floor (stay in CCM, never fully off)
% wp.duty_max is the ceiling - declared above, shared with the team.

%% ---- MPPT mode selection -----------------------------------------------
% 0 = Perturb & Observe        (the spec's plan: one algorithm shared with PV)
% 1 = optimal torque control   (the spec's flagged fallback, T* = k_opt*w^2)
%
% Default is 1, and that is a DELIBERATE change from the spec - see
% docs/wind-model-spec.md section 2. P&O measures 99% in steady wind and 98%
% under turbulence, but only ~62% through a rising ramp: while the wind is
% rising, power goes up after EVERY perturbation regardless of direction, so
% P&O reads every step as a success and keeps walking the wrong way. Measured
% by scripts/wind_scenarios.m, which runs both modes.
%
% P&O is retained, not deleted. Set mppt_mode = 0 to reproduce it.
wp.mppt_mode = 1;

% Inner current loop for torque control. The loop that has to be fast is this
% one; the torque reference itself is a static function of speed, so the
% overall response stays rotor-limited and the bandwidth separation argument
% in the spec is unaffected.
% NOTE: do NOT feed forward d = 1 - V_rect/V_dc here. With a stiff DC bus the
% boost already forces V_rect = (1-d)*V_dc in steady state, so that feedforward
% is satisfied at EVERY operating point and exactly cancels whatever the PI
% does - the loop ends up with no authority over the current. The integrator
% below carries the operating point instead.
wp.f_i_bw = 200;                        % Hz  current loop bandwidth
wp.Kp_i   = 2*pi*wp.f_i_bw*wp.L_boost/wp.V_dc;
wp.Ki_i   = wp.Kp_i*2*pi*wp.f_i_bw/10;  % integral zero a decade below crossover
end
