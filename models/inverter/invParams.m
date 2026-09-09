function ip = invParams()
%INVPARAMS  Single source of truth for the grid-tie inverter branch.
%
% Every inverter model reads from here. Never hard-code a value into a block
% mask - change it here, so the models cannot drift apart.
% Same contract as models/wind/windParams.m.
%
% Owner: Duc Pham (inverter + LCL filter)
% Verified by models/inverter/inv_model_check.m
% Structure enforced by models/inverter/inv_model_lint.m
%
%   ip = invParams();
%
% SCOPE (as of this file): the 120-degree conduction (six-step) switched
% bridge, run standalone into a resistive load. This is the gating and
% topology validation step, not the deliverable inverter. The deliverable is
% SVPWM with dq-frame PI current control and an SRF-PLL (README), behind an
% LCL filter. What survives that change: the parameters below, the block
% interface, and everything except the body of the Gating subsystem.

%% ---- Interface to the rest of the team (shared - do not diverge) ------
% V_dc is the SHARED DC bus. windParams.wp.V_dc and the harness both carry
% 700 V; if this number moves, it moves in all three. The bus capacitor is
% NOT owned here - it lives with the DC-link loop in the integration model
% (P.plant.C = 44 mF, TestHarness/config/harnessParams.m, Hoang).
ip.V_dc     = 700;      % V    shared DC bus nominal
ip.V_ll     = 400;      % V    grid line-to-line rms at the PCC
ip.f_grid   = 50;       % Hz   grid frequency
ip.S_rated  = 150e3;    % VA   inverter rating (under the 200 kVA AS/NZS 4777.2 ceiling)

%% ---- Design assumptions (the only free choices) -----------------------
ip.f_sw     = 10e3;     % Hz   switching frequency. NOT used by 120-degree mode,
                        %      which switches at 6*f_grid = 300 Hz. Declared here
                        %      because the LCL sizing and the SPWM carrier both
                        %      need it, and it should match the PV/wind boosts
                        %      (wp.f_sw = 10 kHz) so one carrier study covers all.
ip.P_test   = 50e3;     % W    standalone test load, ~1/3 of rating. Large enough
                        %      that device drops show, small enough to stay away
                        %      from the current limit while the gating is unproven.

%% ---- Devices ----------------------------------------------------------
% Per-device values, matching windParams.wp.Vf_dev / wp.Ron_dev so the two
% branches do not model the same silicon differently.
ip.Vf_dev   = 0.8;      % V    forward drop of one IGBT or one diode
ip.Ron_dev  = 1e-3;     % ohm  on-resistance of one device
ip.Goff_dev = 1e-6;     % S    off-state conductance
% Converter (Three-Phase) defaults its gate threshold to 6 V, so 0/1 logic
% pulses leave the bridge dark and the model silently produces nothing.
ip.Vth_gate = 0.5;      % V    gate threshold

%% ---- Sample times -----------------------------------------------------
% 0.5 us rather than the wind branch's 1 us: at f_sw = 10 kHz the PWM period is
% 100 us, so the solver step is also the edge resolution of the modulator.
% 1 us quantises the duty to 1%, and that shows up in a THD measurement as an
% artefact of the simulation rather than of the design. 0.5 us halves it and
% still divides the 2 us dead time exactly.
ip.Ts_power = 5e-7;     % s    switched-model solver step
ip.Ts_ctrl  = 1/ip.f_sw;% s    current loop rate

%% ---- Modulator (STUB - Belal owns the real one) -----------------------
% Dead time is NOT optional in the THD answer. Once the LCL has removed the
% switching harmonics, the dead-time error is what is left: it produces 5th and
% 7th harmonics that no LCL can touch, because they are below its corner. A THD
% figure quoted without it is flattering and collapses when real hardware
% assumptions arrive.
ip.t_dead = 2e-6;                              % s  typical for a 150 kVA IGBT at 10 kHz
ip.N_dead = round(ip.t_dead/ip.Ts_power);      % solver steps of blanking per edge

%% ---- Standalone test load (derived - change P_test, not this) ---------
% Balanced wye, floating neutral, resistive. A floating neutral is the point:
% it is what makes the 120-degree phase voltage a quasi-square wave, and it
% is what the LCL and the grid transformer will present later.
ip.V_ph_rms  = (ip.V_dc/2)*sqrt(2/3);        % 285.8 V, see derivation below
ip.R_load    = 3*ip.V_ph_rms^2/ip.P_test;    % 4.90 ohm
ip.L_load    = 0;                            % H, >0 makes the load series RL

%% ---- Derived: six-step closed form ------------------------------------
% 120-degree conduction into a balanced wye R load. Two devices conduct at any
% instant; the third leg floats, so the star point sits midway and the load
% phase voltage is a 120-degree quasi-square wave of amplitude V_dc/2.
% These are what inv_model_check.m and invSim.m check the simulation against.
ip.V_ph1_rms = (4/pi)*(ip.V_dc/2)*sind(60)/sqrt(2);   % 272.9 V fundamental
ip.V_ll_rms  = ip.V_dc/sqrt(2);                       % 495.0 V total
ip.V_ll1_rms = sqrt(3)*ip.V_ph1_rms;                  % 472.7 V = 0.6752*V_dc
ip.THD_ph    = sqrt(ip.V_ph_rms^2 - ip.V_ph1_rms^2)/ip.V_ph1_rms;   % 0.3108
ip.I_ph_rms  = ip.V_ph_rms/ip.R_load;
ip.P_load    = 3*ip.I_ph_rms^2*ip.R_load;

%% ---- LCL filter --------------------------------------------------------
% Sized, not assumed. Three free choices, everything else derived:
%
%   ripple_pu  inverter-side ripple current, as a fraction of rated peak.
%              Sets L1. 10-20% is the usual band: below it the inductor gets
%              large and slow, above it the ripple starts showing up as loss
%              and as current through the filter capacitor.
%   cap_pu     filter capacitance as a fraction of base. Sets Cf, and with it
%              the resonance. Bigger Cf attenuates the switching harmonics
%              harder but drags f_res down towards the current loop, and draws
%              reactive current the inverter has to supply for nothing.
%   r_L        L2/L1. Splitting the inductance is what makes it an LCL rather
%              than an L; the grid-side inductor is what the capacitor works
%              against.
%
% The binding constraint is NOT any of those - it is the current loop. The
% bridge has only V_pi_max of voltage left after feeding the grid, so
% di/dt <= V_pi_max/(L1+L2), and the 2 ms settling spec caps the TOTAL
% inductance at about 0.51 mH. That is what stops this being a bigger filter.
ip.Zbase     = ip.V_ll^2/ip.S_rated;            % 1.067 ohm
ip.Cbase     = ip.S_rated/(2*pi*ip.f_grid*ip.V_ll^2);   % 2.98 mF
ip.ripple_pu = 0.15;                            % of rated peak current
ip.cap_pu    = 0.015;                           % of base capacitance
ip.r_L       = 0.5;                             % L2/L1
ip.Rf_pu     = 0.005;                           % pu  total inductor ESR

ip.I_ripple = ip.ripple_pu*sqrt(2)*ip.S_rated/(sqrt(3)*ip.V_ll);
% Worst-case ripple for a two-level bridge occurs near half modulation:
% dI = V_dc/(6*f_sw*L1)  (Liserre/Blaabjerg/Hansen sizing)
ip.L1  = ip.V_dc/(6*ip.f_sw*ip.I_ripple);       % 0.254 mH  inverter side
ip.L2  = ip.r_L*ip.L1;                          % 0.127 mH  grid side
ip.Cf  = ip.cap_pu*ip.Cbase;                    % 44.8 uF
ip.L_f = ip.L1 + ip.L2;                         % what the current loop sees
                                                % below resonance
ip.R1  = ip.Rf_pu*ip.Zbase*ip.L1/ip.L_f;        % ESR, split with the inductance
ip.R2  = ip.Rf_pu*ip.Zbase*ip.L2/ip.L_f;
ip.R_f = ip.R1 + ip.R2;

% Resonance, and the passive damping that stops the loop exciting it. Rd is
% the standard 1/3 of the capacitor's impedance at resonance: enough to damp,
% small enough that the loss and the lost attenuation stay negligible.
ip.f_res = sqrt(ip.L_f/(ip.L1*ip.L2*ip.Cf))/(2*pi);     % 2584 Hz
ip.Rd    = 1/(3*2*pi*ip.f_res*ip.Cf);                   % 0.46 ohm

% Extra attenuation the LCL gives over a plain L of the same total inductance,
% at the switching frequency: |1/(1 - (f_sw/f_res)^2)|.
ip.atten_fsw = 1/abs(1 - (ip.f_sw/ip.f_res)^2);         % ~1/15

%% ---- Grid stiffness ----------------------------------------------------
% The ee_lib three-phase source DEFAULTS to a 1 MVA short-circuit level. At
% 150 kVA that is SCR 6.7 - a weak grid nobody asked for, putting 0.51 mH in
% series with the filter. Left at the default it destabilises the current loop
% outright: the PCC voltage feedforward then runs through the source impedance
% and closes a positive feedback path. Set explicitly, never left as shipped.
% (Same class of trap as the wind branch's 0.3 ohm boost diode default.)
%   0 = ideal stiff source - correct for tuning the inner loop
%   1 = short-circuit level, for the SCR sweep in the success criteria
ip.grid_Z_opt = 0;
ip.SCR        = 3;                        % only used when grid_Z_opt = 1
ip.S_sc       = ip.SCR*ip.S_rated;        % VA  short-circuit power at the PCC
ip.grid_XR    = 15;                       % -   source X/R

%% ---- Inner current loop (dq frame) ------------------------------------
% Graded spec: settle < 2 ms, overshoot < 10% (README success criteria).
%
% Plant seen by each axis after decoupling is L*di/dt = u - R*i, so a PI whose
% zero cancels the plant pole at R/L leaves a first-order closed loop at the
% crossover: no overshoot in the ideal case, and 2% settling at 4/w_i. At
% 500 Hz that is 1.27 ms, which leaves room for the discretisation lag and the
% decoupling error to eat into it and still make 2 ms.
%
% Why 500 Hz and not faster: the loop runs at Ts_ctrl and the modulator adds
% about another half sample, so roughly 1.5*Ts of delay - 27 deg of phase at
% 500 Hz, leaving ~63 deg of margin. It is also f_sw/20, and 10x the grid
% fundamental, so it neither fights the modulator nor the fundamental.
% inv_model_check.m prints all three margins.
ip.f_i_bw = 500;                               % Hz  current loop bandwidth
ip.w_i    = 2*pi*ip.f_i_bw;
ip.Kp_i   = ip.w_i*ip.L_f;                     % 1.067 V/A
ip.Ki_i   = ip.w_i*ip.R_f;                     % 16.8 V/(A.s) - zero at R/L
ip.wL     = 2*pi*ip.f_grid*ip.L_f;             % ohm, the dq cross-coupling term

% Output limit. The bridge can synthesise a phase voltage peak of V_dc/sqrt(3)
% in the SVPWM linear range - but the grid feedforward already spends most of
% that just standing still. Only the REMAINDER is available to the PI for
% changing the current, and that is what the PI must be limited to. Limiting
% the PI itself to V_max would let the total command ask for 404 + 327 = 731 V,
% which the bridge cannot make; the loop would then be commanding voltage that
% does not exist and the anti-windup would never engage.
ip.V_max     = ip.V_dc/sqrt(3);                % 404.1 V  what the bridge can make
ip.V_grid_pk = ip.V_ll*sqrt(2)/sqrt(3);        % 326.6 V  what the grid takes
ip.V_pi_max  = ip.V_max - ip.V_grid_pk;        %  77.5 V  what is left to steer with
ip.I_pk      = sqrt(2)*ip.S_rated/(sqrt(3)*ip.V_ll);   % 306.2 A rated peak

% That margin is the hard limit on how fast the current can move, whatever the
% gains are: di/dt <= V_pi_max/L_f. It is also a CONSTRAINT ON THE LCL - a
% larger filter inductance directly buys a slower current loop, and the 2 ms
% settling spec puts a ceiling on L_f. inv_model_check.m prints the margin.
ip.didt_max    = ip.V_pi_max/ip.L_f;           % A/s
ip.t_slew_full = ip.I_pk/ip.didt_max;          % s   0 -> rated, best case

% Reactive current reference. Held at zero (unity power factor) until somebody
% owns the Q reference - AS/NZS 4777.2 has power-factor requirements that are
% nobody's task yet. OPEN QUESTION, see README.
ip.Iq_ref = 0;                                 % A

%% ---- Modulation ceilings ----------------------------------------------
% Does a 700 V bus actually reach a 400 V grid? Checked here rather than
% assumed, because it decides whether the bus rating survives contact with
% the inverter. Line-to-line fundamental rms at full modulation:
ip.V_ll1_spwm  = (sqrt(3)/(2*sqrt(2)))*ip.V_dc;  % 428.7 V  sinusoidal PWM, m = 1
ip.V_ll1_svpwm = ip.V_dc/sqrt(2);                % 495.0 V  space-vector PWM
ip.m_spwm      = ip.V_ll/ip.V_ll1_spwm;          % 0.933 - only 7% headroom
ip.m_svpwm     = ip.V_ll/ip.V_ll1_svpwm;         % 0.808 - 24% headroom
% The README specifies SVPWM, and this is the number that justifies it: plain
% SPWM would run at m = 0.93 with nothing left for the LCL voltage drop, the
% current-loop transient, or a low grid. SVPWM leaves 24%.
end
