% inv_model_check.m
% Verifies the inverter sizing that models/inverter/invParams.m asserts.
%
% Reads every constant from invParams.m so this script and the Simulink model
% can never disagree. Plain MATLAB - no toolbox, no Simulink - so anyone on the
% team can run it.
%
% Checks:
%   1. Six-step closed form: what 120-degree conduction produces from V_dc
%   2. Does a 700 V bus actually reach a 400 V grid? (the modulation ceiling)
%   3. Standalone test load against the 150 kVA rating
%   4. Harmonic content, and what it means for the LCL filter
%
% Usage:
%   addpath(genpath('models'));
%   inv_model_check
%
% Owner: Duc Pham

clear; clc;
ip = invParams();

%% ---- 1. Six-step closed form ------------------------------------------
% 120-degree conduction into a balanced wye R load. Two devices conduct at any
% instant and the third leg floats, so the star point sits midway between the
% rails and the load phase voltage is a 120-degree quasi-square wave of
% amplitude V_dc/2.
fprintf('=== 1. 120-degree conduction from V_dc = %g V ===\n', ip.V_dc);
fprintf('  phase voltage V_an     rms = %7.2f V   (V_dc/2 * sqrt(2/3))\n', ip.V_ph_rms);
fprintf('  phase fundamental      rms = %7.2f V\n', ip.V_ph1_rms);
fprintf('  line voltage  V_ab     rms = %7.2f V   (V_dc/sqrt(2))\n', ip.V_ll_rms);
fprintf('  line fundamental       rms = %7.2f V   (%.4f * V_dc)\n', ...
        ip.V_ll1_rms, ip.V_ll1_rms/ip.V_dc);
fprintf('  phase voltage THD          = %7.2f %%\n\n', 100*ip.THD_ph);

assert(abs(ip.V_ll1_rms/ip.V_dc - 0.6752) < 1e-3, ...
       'line fundamental is not 0.6752*V_dc - the 120-degree derivation is wrong');
assert(abs(100*ip.THD_ph - 31.08) < 0.05, ...
       'phase THD is not 31.08%% - check the quasi-square Fourier coefficient');

%% ---- 2. Modulation ceiling: 700 V bus against a 400 V grid -------------
% The question the bus rating turns on. A 400 V grid needs 400 V rms
% line-to-line at the fundamental; each modulation scheme can only reach so
% far from a given V_dc.
fprintf('=== 2. Reaching a %g V grid from a %g V bus ===\n', ip.V_ll, ip.V_dc);
fprintf('  %-26s %-12s %-10s %s\n', 'scheme', 'V_ll1 max', 'needs m', 'headroom');
schemes = { ...
  'SPWM (sinusoidal)',        ip.V_ll1_spwm; ...
  'SVPWM (space vector)',     ip.V_ll1_svpwm; ...
  'six-step, 120 deg',        ip.V_ll1_rms; ...
  'six-step, 180 deg',        0.7797*ip.V_dc};
for k = 1:size(schemes,1)
    V = schemes{k,2};  m = ip.V_ll/V;
    fprintf('  %-26s %8.1f V %9.3f %9.1f %%\n', schemes{k,1}, V, m, 100*(1-m));
end
fprintf('\n');

assert(ip.m_svpwm < 0.95, 'SVPWM has no headroom at this bus voltage');
% SPWM at m = 0.933 leaves 7% for the LCL drop, the current-loop transient and
% a low grid. That is the argument for SVPWM in the README, quantified.
if ip.m_spwm > 0.90
    fprintf('  NOTE: plain SPWM would run at m = %.3f - only %.0f%% spare.\n', ...
            ip.m_spwm, 100*(1-ip.m_spwm));
    fprintf('        SVPWM (m = %.3f) is what makes the 700 V bus comfortable.\n\n', ip.m_svpwm);
end

%% ---- 3. Standalone test load ------------------------------------------
I_rated = ip.S_rated/(sqrt(3)*ip.V_ll);
fprintf('=== 3. Standalone test load ===\n');
fprintf('  P_test    = %6.1f kW  ->  R_load = %.3f ohm\n', ip.P_test/1e3, ip.R_load);
fprintf('  I_ph      = %6.1f A rms  (peak %.1f A)\n', ip.I_ph_rms, (ip.V_dc/2)/ip.R_load);
fprintf('  P_load    = %6.1f kW\n', ip.P_load/1e3);
fprintf('  inverter rated current    = %.1f A rms at %g V\n', I_rated, ip.V_ll);
fprintf('  test load draws %.0f%% of rated current\n\n', 100*ip.I_ph_rms/I_rated);

assert(ip.I_ph_rms < I_rated, 'test load exceeds the inverter current rating');
assert(abs(ip.P_load - ip.P_test) < 1, 'R_load does not deliver P_test');

%% ---- 4. Harmonics, and what the LCL is up against ---------------------
% Six-step has no even and no triplen harmonics; what remains is 6k+/-1, and
% the h-th sits at 1/h of the fundamental.
fprintf('=== 4. Harmonic content of the phase voltage ===\n');
fprintf('  %-8s %-12s %-12s\n', 'order', 'freq [Hz]', 'rms [V]');
h = [1 5 7 11 13 17 19 23 25];
for k = 1:numel(h)
    fprintf('  %-8d %-12.0f %-12.1f\n', h(k), h(k)*ip.f_grid, ip.V_ph1_rms/h(k));
end
f_low = 5*ip.f_grid;
fprintf('\n  lowest harmonic          %4.0f Hz at %.1f%% of fundamental\n', ...
        f_low, 100/5);
fprintf('  under SPWM at f_sw = %g kHz the first cluster sits near %g Hz\n', ...
        ip.f_sw/1e3, ip.f_sw);
fprintf('  ratio to fundamental:    six-step %.0fx   vs   SPWM %.0fx\n', ...
        f_low/ip.f_grid, ip.f_sw/ip.f_grid);
fprintf(['\n  An LCL corner has to sit above the fundamental and below the\n' ...
         '  harmonics it removes. At 250 Hz there is no room: the corner would\n' ...
         '  have to be within 5x of the fundamental, which no practical filter\n' ...
         '  does without distorting the fundamental it is trying to pass.\n' ...
         '  This is why 120-degree mode is a validation step and not the\n' ...
         '  delivered inverter - the <5%% THD target needs SVPWM.\n\n']);

assert(ip.THD_ph > 0.30, 'six-step THD should be about 31% - check the model');

%% ---- 5. Current loop design -------------------------------------------
% Everything here is arithmetic on invParams. inv_current_loop_check.m measures
% the same quantities on the model; if the two disagree, one of them is wrong.
fprintf('=== 5. Inner current loop ===\n');
fprintf('  filter          L_f %.3f mH (L1+L2 of the LCL), R_f %.1f mohm\n', ...
        ip.L_f*1e3, ip.R_f*1e3);
fprintf('  PI              Kp %.4f V/A, Ki %.2f V/(A.s), zero at %.1f rad/s\n', ...
        ip.Kp_i, ip.Ki_i, ip.Ki_i/ip.Kp_i);
fprintf('  plant pole      R_f/L_f = %.1f rad/s  -> %s\n', ip.R_f/ip.L_f, ...
        tern(abs(ip.Ki_i/ip.Kp_i - ip.R_f/ip.L_f) < 1e-6, 'cancelled exactly', 'NOT cancelled'));
assert(abs(ip.Ki_i/ip.Kp_i - ip.R_f/ip.L_f) < 1e-9, ...
       'the PI zero no longer cancels the plant pole');

% Settling: with the pole cancelled the closed loop is first order at w_i.
t_settle = 4/ip.w_i;
fprintf('\n  bandwidth       %g Hz (%.0f rad/s)\n', ip.f_i_bw, ip.w_i);
fprintf('  2%% settling      %.2f ms   (spec < 2 ms)\n', t_settle*1e3);
assert(t_settle < 2e-3, 'bandwidth too low to meet the 2 ms settling spec');

% Three separations that all have to hold at once.
lag_deg = 360*ip.f_i_bw*1.5*ip.Ts_ctrl;         % ~1.5 samples of loop delay
fprintf('\n  %-34s %8s %8s\n', 'separation', 'ratio', 'need');
fprintf('  %-34s %7.1fx %7s\n', 'below switching frequency', ip.f_sw/ip.f_i_bw, '>10x');
fprintf('  %-34s %7.1fx %7s\n', 'above grid fundamental',    ip.f_i_bw/ip.f_grid, '>5x');
fprintf('  %-34s %7.1fx %7s\n', 'above DC-link loop (5 Hz)', ip.f_i_bw/5, '>10x');
fprintf('  loop delay ~1.5*Ts_ctrl = %.0f us -> %.0f deg of phase, margin ~%.0f deg\n\n', ...
        1.5*ip.Ts_ctrl*1e6, lag_deg, 90 - lag_deg);
assert(ip.f_sw/ip.f_i_bw   > 10, 'current loop is too close to the switching frequency');
assert(ip.f_i_bw/ip.f_grid >  5, 'current loop is too close to the fundamental');
assert(90 - lag_deg > 45, 'phase margin below 45 deg once the loop delay is counted');

% Voltage authority - and what it costs the LCL.
fprintf('  voltage the bridge makes     %6.1f V  (V_dc/sqrt(3))\n', ip.V_max);
fprintf('  voltage the grid takes       %6.1f V\n', ip.V_grid_pk);
fprintf('  left for the current loop    %6.1f V  <- this is the whole authority\n', ip.V_pi_max);
fprintf('  fastest di/dt                %6.0f A/ms\n', ip.didt_max/1e3);
fprintf('  0 -> rated slew              %6.2f ms  (spec allows 2 ms)\n', ip.t_slew_full*1e3);
fprintf('  => CONSTRAINT ON THE LCL: L_f <= %.2f mH for a full-rated step in 2 ms\n', ...
        1e3*ip.V_pi_max*2e-3/ip.I_pk);
fprintf('     (currently %.2f mH, so there is room - but not a lot)\n\n', ip.L_f*1e3);
assert(ip.V_pi_max > 0, 'the grid needs more voltage than the bridge can make');
assert(ip.t_slew_full < 2e-3, 'cannot slew to rated current within the settling spec');

%% ---- 6. LCL filter -----------------------------------------------------
fprintf('=== 6. LCL filter ===\n');
fprintf('  L1  %6.3f mH   inverter side, sized for %.0f%% ripple (%.1f A pk-pk)\n', ...
        ip.L1*1e3, 100*ip.ripple_pu, ip.I_ripple);
fprintf('  Cf  %6.2f uF   %.1f%% of base, draws %.0f VAr (%.2f%% of rating)\n', ...
        ip.Cf*1e6, 100*ip.cap_pu, ...
        3*2*pi*ip.f_grid*ip.Cf*(ip.V_ll/sqrt(3))^2, ...
        100*3*2*pi*ip.f_grid*ip.Cf*(ip.V_ll/sqrt(3))^2/ip.S_rated);
fprintf('  L2  %6.3f mH   grid side, L2/L1 = %.2f\n', ip.L2*1e3, ip.r_L);
fprintf('  Rd  %6.3f ohm  passive damping, 1/3 of Cf impedance at resonance\n\n', ip.Rd);

fprintf('  %-36s %10s %12s\n', 'resonance placement', 'value', 'requirement');
fprintf('  %-36s %8.0f Hz %12s\n', 'f_res', ip.f_res, '');
fprintf('  %-36s %9.1fx %12s\n', 'above 10x the fundamental', ip.f_res/(10*ip.f_grid), '> 1x');
fprintf('  %-36s %9.1fx %12s\n', 'below half the switching frequency', (ip.f_sw/2)/ip.f_res, '> 1x');
fprintf('  %-36s %9.1fx %12s\n', 'above the current loop bandwidth', ip.f_res/ip.f_i_bw, '> 4x');
fprintf('  %-36s %9.1fx %12s\n\n', 'attenuation at f_sw vs a plain L', 1/ip.atten_fsw, '');

assert(ip.f_res > 10*ip.f_grid, 'LCL resonance is too close to the fundamental');
assert(ip.f_res < ip.f_sw/2,    'LCL resonance is above half the switching frequency');
assert(ip.f_res > 4*ip.f_i_bw,  'LCL resonance is too close to the current loop bandwidth');

% The constraint that actually sized this filter.
Lmax = ip.V_pi_max*2e-3/ip.I_pk;
fprintf('  total inductance   %.3f mH  against the %.3f mH the current loop\n', ip.L_f*1e3, Lmax*1e3);
fprintf('                     allows -> %.0f%% margin. THIS is what caps the filter,\n', ...
        100*(1 - ip.L_f/Lmax));
fprintf('                     not ripple or attenuation.\n\n');
assert(ip.L_f < Lmax, 'LCL inductance exceeds what the 2 ms settling spec allows');

fprintf('  Note: the LCL attenuates at and above f_res. The 5th and 7th from dead\n');
fprintf('  time sit at %g and %g Hz, far BELOW f_res, so the filter does nothing\n', ...
        5*ip.f_grid, 7*ip.f_grid);
fprintf('  about them - the current loop rejects those, because they are inside\n');
fprintf('  its %g Hz bandwidth. inv_grid_thd_check measures both effects.\n\n', ip.f_i_bw);

fprintf('  All checks passed.\n');

% -------------------------------------------------------------------------
function s = tern(c, a, b)
if c, s = a; else, s = b; end
end
