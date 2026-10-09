function xp = intParams()
%INTPARAMS  Parameters the INTEGRATION model owns - nothing else.
%
%   xp = intParams()
%
% Everything a component owner already defines stays in their file:
%   ip = invParams()    Duc   - inverter, LCL, current loop, grid
%   wp = windParams()   Huy   - turbine, PMSG, wind boost
%   Belal's PV model carries its own numbers on its blocks.
% This file holds only what lives BETWEEN them: the shared bus capacitor, the
% two stand-in controllers that fill Aqib's gap, and the integration solver step.
%

ip = invParams();

%% ---- Solver ------------------------------------------------------------
% One fixed step for the whole system. It has to be the inverter's 0.5 us:
% at 10 kHz switching the step is also the PWM edge resolution (see
% models/inverter/README.md), and a step coarser than that shows up in THD as a
% simulation artefact.
xp.Ts      = ip.Ts_power;       % s    base step           (0.5 us)
xp.Ts_ctrl = ip.Ts_ctrl;        % s    controller rate     (100 us = f_sw)

%% ---- The shared DC bus -------------------------------------------------
% C * dVdc/dt = i_pv + i_wind - i_inv
% 44 mF comes from TestHarness/config/harnessParams.m (P.plant.C), where the DC
% loop was tuned and 9/9 spec tests pass. Kept identical here on purpose, so the
% harness result carries over. NOTE: 44 mF is large for 150 kVA (industry is
% a few mF). It came from scaling the 8 kW design x20. Revisit, but not today.
xp.C_bus   = 44e-3;             % F
xp.Vdc0    = ip.V_dc;           % V    initial bus voltage
xp.Vdc_ref = ip.V_dc;           % V    bus setpoint

%% ---- DC-link voltage loop  (STAND-IN for Aqib) ------------------------
% Same design as the harness: Kp = C*wc puts crossover at wc, Ki = Kp*wc/10
% puts the PI zero a decade below. The harness loop commands DC current. The
% real inverter takes Id_ref (A peak, d axis), so convert by power balance:
%     P = 1.5 * Vgd * Id = Vdc * i_dc   ->   Id = i_dc * Vdc / (1.5*Vgd)
% Sign: e = v_dc - Vdc_ref. The bus rising means more is coming in than going
% out, so export more: Id_ref goes up.
xp.Vgd       = ip.V_grid_pk;                   % V pk  326.6
xp.dc.Kp     = 18.714;                         % A_pk/V    from Control System Designer: C = 18.714(s+94.79)/s
xp.dc.Ki     = 18.714*94.79;                   % A_pk/V/s  = K x zero = 1774
xp.dc.Id_max = ip.I_pk;                        % A pk  306.2 = 150 kVA. The clip.

%% ---- SRF-PLL  (STAND-IN for Aqib) -------------------------------------
% Clarke -> Park on the estimated angle -> PI drives vq to zero -> integrate w.
% vq is normalised by the nominal peak, so near lock vq_n ~ (theta - theta_hat)
% and the loop is  s^2 + Kp*s + Ki :  wn = sqrt(Ki),  zeta = Kp/(2*wn).
% 20 Hz, zeta 0.707 -> settles in ~45 ms. It sits well below the 500 Hz current
% loop. The DC loop (32 Hz) is a parallel outer loop, not nested inside the
% PLL, so the two being close is fine.
xp.pll.fn     = 20;                            % Hz
xp.pll.zeta   = 1/sqrt(2);
xp.pll.wn     = 2*pi*xp.pll.fn;
xp.pll.Kp     = 2*xp.pll.zeta*xp.pll.wn;       % rad/s per unit vq  177.7
xp.pll.Ki     = xp.pll.wn^2;                   % rad/s^2 per unit vq 15791
xp.pll.w0     = 2*pi*ip.f_grid;                % rad/s feed-forward frequency
xp.pll.Vm     = xp.Vgd;                        % V pk  normalisation
% The ee_lib grid source is va = Vm*sin(wt), so the Clarke angle at t = 0 is
% -pi/2 (measured: GridAngle_ideal outputs -1.571 at the first sample). Starting
% there means "PLL already locked when the contactor closes", which is how a
% real inverter starts. Set pll.theta0 = 0 in a scenario to test lock-in.
xp.pll.theta0 = -pi/2;                         % rad

%% ---- Trip path  (the trip SIGNAL is a STAND-IN for Redhwan's) ----------
% One trip stops everything that pushes power: inverter current references to
% zero, wind boost enable off, PV boost stops switching. A Step fires it at
% xp.trip.t until Redhwan's 47/52 Hz trip is wired in. 1e6 s = never (the
% Step block refuses Inf).
xp.trip.t = 1e6;                               % s

%% ---- Anti-islanding: Redhwan's relay + SFS perturbation (5 Oct, Claude) --
% Values from models/protection/protectionParams.m and design-record.md.
% Relay = protectionLib/AntiIslandingRelay (linked, not copied). Its trip is
% OR'd with the stand-in trip above, so both test paths keep working.
xp.prot.f_min    = 47;                         % Hz  AS/NZS 4777.2 (Redhwan #1, #2)
xp.prot.f_max    = 52;                         % Hz
xp.prot.t_pickup = 0.05;                       % s   out of band this long to trip (#4b)
% t_arm: relay blocked before this. Must clear Aqib's PLL start-up (up to
% 170 ms out of band, Redhwan #4a) and come before our island (0.5 s).
xp.prot.t_arm    = 0.3;                        % s   (Redhwan's rig uses 0.5; its island is at 1.0 s)
% SFS: rotate the current reference by theta = (pi/2)*cf, cf = cf0 + kSFS*(f - f0),
% |cf| <= cf_max. Rotation form (Redhwan section 8): magnitude kept, vector turned.
% Set cf0 = kSFS = 0 to switch SFS off.
xp.sfs.f0     = ip.f_grid;                     % Hz
xp.sfs.cf0    = 0.05;                          % -   base chopping factor (4.5 deg)
xp.sfs.kSFS   = 0.05;                          % 1/Hz positive feedback (rad/Hz in his notes)
xp.sfs.cf_max = 0.5;                           % -   bound (45 deg)
xp.sfs.sign   = 1;                             % +1: theta > 0 makes the current LEAD the voltage
% SFS acts on a SMOOTHED frequency: Redhwan's rig measures f once per cycle from zero
% crossings; Aqib's PLL estimate ripples +/-1.5 Hz at 100-300 Hz on a weak grid, and
% feeding that ripple straight into SFS made the SCR-3 run unstable (5 Oct). First-order
% low-pass, one cycle. SFS also starts only once the PLL has settled (at xp.prot.t_arm).
xp.sfs.tau_f  = 0.02;                          % s

%% ---- PCC: site load, RLC test load, grid, each on its own breaker ------
% Breaker command = OPEN command: open0 = 1 means open at t = 0, and the
% command flips at t (1e6 s = never). Loads are set from t = 0 (see the
% Protection_PCC_LabManual, A4).
xp.pcc.grid.open0 = 0;   xp.pcc.grid.t = 1e6;  % normal: grid connected

% Site load, docs/decisions.md 2026-09-05: 250 kW constant PQ, no Q given -> unity PF.
xp.pcc.site.P = 250e3;                         % W
xp.pcc.site.Q = 0;                             % var
xp.pcc.site.open0 = 0;   xp.pcc.site.t = 1e6;  % normal: connected

% RLC test load: parallel R-L-C at 50 Hz, Qf = 1, matched to the nominal export
% (117.0 kW). As in models/protection/protectionParams.m, Cf's var is trimmed off.
xp.pcc.rlc.P  = 117e3;                         % W
xp.pcc.rlc.Qf = 1;
xp.pcc.rlc.QL = xp.pcc.rlc.Qf*xp.pcc.rlc.P;    % var inductive
xp.pcc.rlc.QC = xp.pcc.rlc.QL - 2*pi*ip.f_grid*ip.Cf*ip.V_ll^2;  % var capacitive
xp.pcc.rlc.open0 = 1;    xp.pcc.rlc.t = 1e6;   % normal: a test fixture, out

%% ---- Logging -----------------------------------------------------------
% Decimation relative to the 0.5 us base step. Fast signals at 5 us (200 kHz,
% enough for THD to well past the 10 kHz sidebands); slow ones at 50 us.
xp.log.fast = 10;
xp.log.slow = 100;
end
