function pp = protectionParams()
%PROTECTIONPARAMS Anti-islanding / SFS parameters. Single source of truth.
%   Single-phase equivalent of one phase of the three-phase plant. Every
%   rating derives from the plant nameplate, so the whole file follows from
%   pp.S_plant.
%
%   Cross-checked against models/inverter/invParams.m (Duc, merged to main
%   2026-09-16). Shared quantities agree by construction:
%
%       ip.S_rated = 150e3   ->  pp.S_plant
%       ip.V_ll    = 400     ->  pp.V_ll
%       ip.I_pk    = 306.2 A ->  pp.Ipvmax
%       ip.Ts_ctrl = 1e-4 s  ->  pp.Ts
%       ip.Cf      = 44.8 uF ->  pp.Cf
%
%   See also RLCTESTLOAD, PROTECTION_FIGURES

% --- Plant nameplate, settled Sept 2026 ----------------------------------
pp.S_plant = 150e3;                   % VA, three-phase inverter rating
pp.n_ph    = 3;                       % phases

% --- Grid ----------------------------------------------------------------
pp.f_n  = 50;                         % Hz
pp.V_ll = 400;                        % V rms, line-to-line at the PCC
pp.V_ph = pp.V_ll/sqrt(3);            % 230.94 V rms, phase to neutral
pp.w_n  = 2*pi*pp.f_n;
pp.Vg_amp = sqrt(2)*pp.V_ph;          % 326.6 V peak, AC Voltage Source amplitude

% --- Per-phase equivalent ------------------------------------------------
%   The model is one phase of three. Using the three-phase nameplate here
%   would overstate the current by a factor of three.
pp.S_rated = pp.S_plant/pp.n_ph;      % 50 kVA per phase
pp.P_inv   = pp.S_rated;              % W, unity power factor (ip.Iq_ref = 0)
pp.Ipvmax  = sqrt(2)*pp.P_inv/pp.V_ph;% 306.2 A peak -- equals ip.I_pk

% --- SFS tuning ----------------------------------------------------------
%   Detection needs kSFS > 4*Qf/(pi*f_n) so the SFS phase-frequency slope
%   exceeds the load's. At Qf = 1, f_n = 50 that floor is 0.0255; 0.05 gives
%   roughly 2x margin. VERIFY the derivation against IEEE 1547.1 before it
%   goes in the report.
pp.Qf       = 1.0;                    % test-load quality factor (per standard)
pp.cf0      = 0.05;                   % base chopping factor
pp.kSFS     = 0.05;                   % rad/Hz positive-feedback gain
pp.kSFS_min = 4*pp.Qf/(pi*pp.f_n);    % analytical floor, for reference

% --- LCL filter capacitance seen at the PCC ------------------------------
%   The inverter's output filter capacitor sits electrically at the PCC and
%   is part of the load the island sees. The standard specifies the TOTAL
%   load as resonant at f_n with quality factor Qf, so the RLC bank is
%   trimmed by Cf rather than ignoring it.
pp.Cf = 44.8e-6;                      % F per phase, wye -- ip.Cf

% --- Matched RLC test load (AS/NZS 4777.2 / IEEE 1547.1 island circuit) ---
%   Parallel R-L-C resonant at f_n with quality factor Qf, matched to
%   inverter output. This is the WORST CASE for passive detection, and it is
%   the only load present during the islanding test -- the 250 kW site load
%   is disconnected, otherwise the power deficit collapses the island and
%   undervoltage protection detects it trivially.
pp.R_load = pp.V_ph^2/pp.P_inv;       % 1.067 ohm
pp.C_tot  = pp.Qf/(pp.w_n*pp.R_load); % 2984 uF total capacitance required
pp.C_load = pp.C_tot - pp.Cf;         % 2939 uF in the RLC bank itself
pp.L_load = pp.R_load/(pp.w_n*pp.Qf); % 3.395 mH

% --- Inductor initial condition ------------------------------------------
%   A lossless inductor energised at t = 0 keeps its startup DC component
%   forever, because nothing in that branch dissipates it. Starting the
%   branch in steady state avoids the offset without adding loss, which
%   would change Qf and invalidate the test load.
pp.iL0 = -pp.Vg_amp/(pp.w_n*pp.L_load);   % A, inductor current at t = 0

% --- Trip thresholds (CONFIRM against AS/NZS 4777.2 table) ---------------
pp.f_min = 47.0;         % Hz
pp.f_max = 52.0;         % Hz
pp.t_trip_max = 2.0;     % s, success criterion SC5

% --- Simulation timing ---------------------------------------------------
pp.t_island = 1.0;       % s, breaker opens (settle first, then island)
pp.t_stop   = 3.0;       % s, t_island + t_trip_max, with margin

% --- Digital controller rate ---------------------------------------------
%   The SFS current reference is applied one control cycle after the voltage
%   that produced it, as in a real DSP implementation. This delay is what
%   makes the SFS feedback path solvable: without it the injected current
%   and the PCC voltage it produces form an algebraic loop. Matches
%   ip.Ts_ctrl, and the inverter branch uses the same one-sample delay in
%   its CurrentLoop for the same reason.
pp.Ts = 1e-4;            % s, 10 kHz control rate
end
