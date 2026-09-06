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
%
% SCALE + ARCHITECTURE (decision record, docs/decisions.md, 5 Sep 2026): the
% plant is DC-COUPLED - one shared 700 V DC bus, one 150 kVA grid-tie inverter -
% and sized for a 250 kW light-industrial site. The wind branch is rated 60 kW.
% The AC-coupled / 30 kW design worked on 3-5 Sep was not adopted; decisions.md
% records why (inverter cost falls with size at 150 kVA, and a grid-connected
% site behind the meter does not need N-1 on its generation).
%
% Rating history: 3 kW (proposal) -> 30 kW (4 Sep, AC-coupled draft) -> 60 kW
% (6 Sep, this file). Each step is a clean per-unit scaling: every voltage,
% duty, tip-speed ratio and time constant is unchanged; currents, powers and
% inertia move with the rating, rotor radius with its square root, impedances
% inversely. The validated operating points therefore carry over - see
% scripts/wind_scenarios.m for the re-run at 60 kW.

%% ---- Design assumptions (the only free choices) -----------------------
wp.P_elec   = 60000;    % W    rated electrical output (docs/decisions.md, 5 Sep 2026)
wp.v_rated  = 12;       % m/s  ASSUMPTION - not from proposal, see README
wp.v_cutin  = 4;        % m/s  ASSUMPTION - set by max boost duty 0.85
wp.eta      = 0.90;     % -    source-to-DC-link efficiency
wp.rho      = 1.225;    % kg/m^3
wp.p        = 20;       % -    pole pairs (direct drive; was 16 at 30 kW, 10 at 3 kW - see note)
wp.H        = 3;        % s    inertia constant
wp.V_rect_r = 400;      % V    target rectified voltage at rated wind

% Pole pairs: the 60 kW rotor is sqrt(20) = 4.5x larger than the 3 kW one and
% turns 4.5x slower (144 rpm). At p = 10 the electrical frequency would be
% 24 Hz; at p = 16 (the 30 kW choice) 38 Hz. p = 20 puts it at 48 Hz, in the
% 40-55 Hz band that commercial direct-drive PMSGs run at around 100-200 rpm
% (a 150 rpm machine wound for 50 Hz has 20 pole pairs). Only lam_pm and the
% pu stator inductance depend on it; nothing graded does. ASSUMPTION - flagged
% in README.

%% ---- Interface to the rest of the team --------------------------------
% DC-coupled: V_dc is the SHARED DC bus, held at 700 V by the 150 kVA
% inverter's DC-link voltage loop (Aqib / Duc). The wind branch sees it as a
% stiff voltage and injects current into it, exactly as PV does. The bus
% capacitor (44 mF, TestHarness/config/harnessParams.m) is owned by
% integration, not by this file - exactly one place owns C_dc.
wp.V_dc     = 700;      % V    shared DC bus nominal (regulated by the inverter)
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
wp.R       = sqrt(wp.A/pi);                             % 6.463 m (D = 12.93 m)
wp.w_rated = wp.lam_opt*wp.v_rated/wp.R;                % 15.04 rad/s (144 rpm)
wp.f_e     = wp.p*wp.w_rated/(2*pi);                    % 47.9 Hz

% PMSG: flux linkage set so the 6-pulse bridge gives V_rect_r at rated speed
wp.V_ll    = wp.V_rect_r/1.35;                          % 6-pulse: Vdc = 1.35*Vll
wp.lam_pm  = (wp.V_ll*sqrt(2)/sqrt(3))/(wp.p*wp.w_rated);   % 0.804 Wb
wp.J       = 2*wp.H*wp.P_mech/wp.w_rated^2;             % 1768 kg.m^2

% Optimal torque coefficient, T = k*w^2 (fallback MPPT if P&O hunts)
wp.k_opt   = 0.5*wp.rho*pi*wp.R^5*wp.Cp_max/wp.lam_opt^3;

%% ---- Machine electricals (scaled with the rating - refine in W5) -------
% Same per-unit values as the validated 3 kW and 30 kW machines (Rs ~ 0.017 pu,
% Xs ~ 0.19 pu on Z_base = V_ll^2 / P_elec = 1.46 ohm). Halving the base
% impedance from 30 kW halves Rs; Ls also carries the 54 -> 48 Hz change in
% w_e, so it is 1.6 mH * 0.5 * (54/48) = 0.9 mH.
wp.Rs = 0.025;          % ohm   stator resistance             (was 0.05 at 30 kW)
wp.Ls = 0.9e-3;         % H     stator inductance, Ld = Lq    (was 1.6e-3)

%% ---- Converter + sample times -----------------------------------------
wp.f_sw     = 10e3;     % Hz   boost switching frequency
wp.L_boost  = 0.25e-3;  % H    boost inductor (was 0.5e-3 at 30 kW). Sized for
                        %      the same ~35% pk-pk ripple at rated:
                        %      di = V_rect*d/(L*f_sw) ~ 70 A on ~190 A mean
wp.Ts_power = 1e-6;     % s    switched-model solver step
wp.Ts_ctrl  = 1/wp.f_sw;% s    boost current loop
wp.Ts_mppt  = 5.0;      % s    P&O perturbation period - see note below

% Switched model only: the rectifier-side smoothing capacitor and the
% per-device diode drop and on-resistance. wp.V_f below is the drop across the
% TWO devices conducting in the bridge at any instant; the switched model
% needs the single-device value.
wp.C_rect   = 2e-3;     % F    rectifier-side smoothing capacitor (was 1e-3 at
                        %      30 kW; same pu impedance at 2x the current)
wp.R_Crect  = 0;        % ohm  its series resistance. Zero = ideal, and that is a
                        %      stated choice, not a block default left in place;
                        %      wind_model_lint.m flags any design value that is
                        %      still a literal in a mask.
wp.Vf_dev   = 0.8;      % V    forward drop of one diode
wp.Ron_dev  = 1e-3;     % ohm  on-resistance of one device: bridge diodes,
                        %      boost diode and IGBT all read this.
% NOTE on Ron_dev: the boost diode previously sat at the Simscape block
% default of 0.3 ohm. At 3 kW that was 1.4 V / 7 W (invisible); at 60 kW it
% would be 28 V / 2.7 kW - 4.5% of the rating, and it would show up in the
% fidelity check as a switched-vs-averaged gap that is not real.

% NOTE: the DC-bus capacitor is NOT defined here. It is the shared bus,
% regulated by the 150 kVA inverter's voltage loop; its capacitor lives with
% the DC-link loop in the integration model and the test harness (Hoang).
% Exactly one place owns C_dc.

%% ---- Loss + parasitic terms (needed by the Simulink models) -----------
% Small but not optional: without them the averaged boost has no damping and
% the rectifier looks like an ideal source, which flatters the MPPT result.
wp.B      = 0.01*(wp.P_mech/wp.w_rated)/wp.w_rated;  % N.m.s viscous damping
                                                     % (1% of rated torque at rated speed)
wp.R_L    = 0.005;      % ohm  boost inductor ESR (was 0.01 at 30 kW; same pu loss)
wp.V_f    = 1.6;        % V    diode bridge forward drop (2 devices conducting)

%% ---- Model initial conditions -----------------------------------------
% Start at the 8 m/s operating point: that is the initial condition of the
% 8 -> 12 m/s step scenario, so the model starts settled instead of spending
% the first seconds of every run spinning up from rest.
wp.v_init  = 8;                                   % m/s
wp.w_init  = wp.lam_opt*wp.v_init/wp.R;           % rad/s  = 10.0
wp.iL_init = 0;                                   % A

% Rectified voltage at the initial operating point, used to seed the duty so
% the boost does not slam the bus at t = 0.
wp.V_rect_init = 1.35*(wp.p*wp.w_init*wp.lam_pm)*sqrt(3)/sqrt(2);
wp.d_init      = 1 - wp.V_rect_init/wp.V_dc;

%% ---- P&O MPPT tuning ---------------------------------------------------
% MEASURED, not assumed. Ts_mppt must be LONGER than the rotor settling time
% (4.78 s - unchanged by the rescale, because H, lambda_opt and the Cp curve
% are unchanged), or P&O reads the rotor's transient instead of the new steady
% state and walks the wrong way. Tracking efficiency at 12 m/s, against what
% the plant can actually deliver (open-loop duty sweep, scripts/wind_mppt_sweep.m,
% re-run at 60 kW on 6 Sep 2026):
%
%   Plant delivers 63726 W at duty 0.500 - 95.6% of the 66667 W in the wind;
%   the rest is rectifier + boost loss, not tracking error. Efficiency vs
%   (Ts_mppt, dD), as % of that 63726 W:
%
%   Ts_mppt:       0.5 s     1 s     2 s     5 s
%   dD = 0.002    97.7%   97.7%   93.6%   94.4%
%   dD = 0.005    56.2%   94.6%   98.2%   99.1%   <- chosen
%   dD = 0.010    91.0%   55.6%   94.8%   98.0%
%   dD = 0.020    73.2%   91.2%   31.3%   89.7%
%
% The 31-56% cells are the hunting failure the spec flagged as a risk - it is
% real, and it is roughly what the original 0.1 s perturbation period gave.
% 5 s / 0.005 was chosen for its neighbourhood, not just its peak: the worst
% adjacent setting is still above 93% (93.6%), so it survives the plant changing slightly.
wp.dD      = 0.005;     % -    duty perturbation step
wp.d_min   = 0.05;      % -    duty floor (stay in CCM, never fully off)
% wp.duty_max is the ceiling - declared above, shared with the team.

%% ---- MPPT mode selection -----------------------------------------------
% 0 = Perturb & Observe        (the spec's plan: one algorithm shared with PV)
% 1 = optimal torque control   (the spec's flagged fallback, T* = k_opt*w^2)
%
% Default is 1, and that is a DELIBERATE change from the spec - see
% docs/wind-model-spec.md section 2. P&O tracks 96-99% in steady and
% turbulent wind but only ~74% through a rising ramp: while the wind is
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
% Kp_i scales with L_boost, so the smaller inductor gives a proportionally
% smaller gain and the same 200 Hz bandwidth.
wp.f_i_bw = 200;                        % Hz  current loop bandwidth
wp.Kp_i   = 2*pi*wp.f_i_bw*wp.L_boost/wp.V_dc;
wp.Ki_i   = wp.Kp_i*2*pi*wp.f_i_bw/10;  % integral zero a decade below crossover
end
