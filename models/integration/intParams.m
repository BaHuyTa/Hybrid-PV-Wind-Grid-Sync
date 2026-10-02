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

%% ---- Logging -----------------------------------------------------------
% Decimation relative to the 0.5 us base step. Fast signals at 5 us (200 kHz,
% enough for THD to well past the 10 kHz sidebands); slow ones at 50 us.
xp.log.fast = 10;
xp.log.slow = 100;
end
