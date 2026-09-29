function m = pvIECEfficiency(out, P, meta)
%PVIECEFFICIENCY MPPT efficiency as the standard defines it: energy, not power.
%
%   m = pvIECEfficiency(out, P, meta)
%
%   EN 50530 3.4.1 / IEC 62891: eta_MPPT = integral(P_DC) / integral(P_MPP)
%   over the measuring period. P_DC is what the converter actually drew from the
%   panel; P_MPP is what the panel could have given at that instant.
%
%   Numerator: the model integrates V*I itself (pvUUT_iec), so the energy is
%   exact at solver resolution even though it is only sampled every 1 ms.
%   Denominator: the swept maximum-power reference (pvReference), interpolated
%   across irradiance for the dynamic runs, where the available power moves
%   with the ramp. Both are panel-side quantities, so converter losses are not
%   counted against the tracker -- the standard separates those as conversion
%   efficiency, and so does this.

% Every field exists for both kinds, in the same order, so static and dynamic
% results concatenate into one struct array.
m = struct(scenario = meta.scenario, kind = meta.kind, T = meta.T, ...
           levelPct = NaN, seq = ' ', slope = NaN, cycles = NaN, ...
           duration = NaN, energyOut = NaN, energyAvail = NaN, etaPct = NaN, ...
           refReachable = true, trace = []);

L  = out.logsout;
E  = L.getElement("E").Values;
Vs = L.getElement("Vs").Values;
Ds = L.getElement("Ds").Values;

t0 = meta.evalStart;
% The 1 ms samples can stop a hair short of StopTime; integrate numerator and
% denominator over the same, actually-logged interval.
t1 = min(meta.evalEnd, E.Time(end));
Et = @(t) interp1(E.Time, E.Data, t, "linear");
m.energyOut = Et(t1) - Et(t0);                       % [J]

% Available power over time: P_MPP(G(t)) at this run's cell temperature.
% linspace, not t0:1e-3:t1 -- the colon form drops the last point whenever
% floating-point rounding leaves the span a hair under a whole number of steps,
% which shortened the denominator by 1 ms in 500 and scored a tracker sitting
% on the peak at 100.17 %.
tg = linspace(t0, t1, ceil((t1 - t0)/1e-3) + 1)';
Gt = interp1(meta.irrProfile.Time, meta.irrProfile.Data, tg, "linear");
if meta.kind == "static"
    ref      = pvReference(meta.irrFinal, P, T = meta.T, Quiet = true);
    Pmpp     = repmat(ref.Pmax, size(tg));
    m.refReachable = ref.reachable;
else
    [Gc, Pc, reach] = mppCurve(meta, P);
    Pmpp     = interp1(Gc, Pc, Gt, "pchip");
    m.refReachable = all(reach);
end
m.energyAvail = trapz(tg, Pmpp);                     % [J]
m.etaPct      = 100 * m.energyOut / m.energyAvail;

m.duration = t1 - t0;
if meta.kind == "static"
    m.levelPct = meta.levelPct;
else
    m.seq = meta.seq; m.slope = meta.slope; m.cycles = meta.cycles;
end

% Traces for plotting: mean panel power per 1 ms from the energy integral.
Pms = [NaN; diff(E.Data) ./ diff(E.Time)];
m.trace = struct(t = E.Time, P = Pms, V = Vs.Data, D = Ds.Data, ...
                 tRef = tg, Pmpp = Pmpp, G = Gt);
end

% -----------------------------------------------------------------------------
function [G, Pmax, reach] = mppCurve(meta, P)
%MPPCURVE Swept maximum power across the irradiance range this sequence covers.
seq  = P.iec.dynamic.seq(double(meta.seq) - double('A') + 1);
pct  = P.iec.dynamic.refGridPct;
pct  = pct(pct >= seq.lowPct & pct <= seq.highPct);
G    = 10 * pct;
Pmax = zeros(size(G)); reach = true(size(G));
for k = 1:numel(G)
    r = pvReference(G(k), P, T = meta.T, Quiet = true);
    Pmax(k) = r.Pmax; reach(k) = r.reachable;
end
end
