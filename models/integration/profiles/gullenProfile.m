function p = gullenProfile(opts)
%GULLENPROFILE  A real day of sun and wind, compressed into a few seconds of simulation.
%
%   p = gullenProfile()                       6 Oct 2026, 06:00-14:00, 5 min -> 50 ms
%   p = gullenProfile(Step=0.1)               5 min -> 100 ms
%
% Source: AEMO NEMWEB Dispatch_SCADA (public), 5-minute measured output of the
% Gullen Range site near Goulburn, NSW, which has a solar farm (GULLRSF1, 10 MW)
% and a wind farm (GULLRWF1 + GULLRWF2) side by side, so one day gives both
% resources under the same weather. gullen_2026-10-06.csv holds the raw rows.
% Times are NEM market time (AEST, UTC+10, interval ending); local clock that day
% was AEDT, one hour later.
%
% Why this day (19 Oct, scored over 1 Sep - 17 Oct 2026): sunrise ramp, wind
% rising 10 -> 42 kW (scaled), two hours with PV + wind above the 150 kVA rating,
% heavy cloud after noon, no negative NSW price while the sun was up (so the solar
% farm was not curtailing itself), and no interval where both farms drop to zero
% together (a network constraint, not weather; it rules out 10 and 12 Oct).
%
% Scaling to our plant (assumptions, stated in RESULTS.md):
%   G     = 1000 W/m^2 x PV farm output / 9.90 MW. Farm output is taken as
%           proportional to irradiance; the farm clips at its rating, so the
%           brightest hours read as 1000 W/m^2.
%   v_wind= 12 m/s x (wind farm output / 265.8 MW)^(1/3). Inverts our turbine's
%           cubic curve below rated (P ~ v^3 under optimal-torque MPPT, rated at
%           12 m/s), so the scaled wind power follows the farm's. Floor 3 m/s.
% 9.90 and 265.8 MW are the 99.9th percentiles over the 47 days.

arguments
    opts.File (1,1) string = fullfile(fileparts(mfilename('fullpath')), "gullen_2026-10-06.csv")
    opts.Step (1,1) double = 0.05        % s of simulation per 5-minute sample
end
T = readtable(opts.File, 'TextType','string');
tr = datetime(T.time_aest, 'InputFormat','yyyy/MM/dd HH:mm:ss');
p.t_real = tr;
p.t      = opts.Step * minutes(tr - tr(1)) / 5;               % s, simulation time
p.pv_pu  = min(max(T.GULLRSF1_MW / 9.90, 0), 1);
p.w_pu   = min(max((T.GULLRWF1_MW + T.GULLRWF2_MW) / 265.8, 0), 1);
p.G      = 1000 * p.pv_pu;                                    % W/m^2
p.v      = max(3, 12 * p.w_pu.^(1/3));                        % m/s
p.T      = p.t(end);
p.step   = opts.Step;
p.compression = 300 / opts.Step;                              % real s per simulated s
% Linear between samples; held flat outside.
p.Gf = @(t) interp1(p.t, p.G, min(max(t, 0), p.T), 'linear');
p.vf = @(t) interp1(p.t, p.v, min(max(t, 0), p.T), 'linear');
% Simulation time of a clock time on that day, e.g. p.at("10:00")
p.at = @(hhmm) opts.Step * minutes(datetime(string(datestr(tr(1),'yyyy-mm-dd')) + " " + hhmm, ...
    'InputFormat','yyyy-MM-dd HH:mm') - tr(1)) / 5;
end
