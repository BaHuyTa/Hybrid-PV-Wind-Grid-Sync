function m = evaluateSpec(out, ds, P, meta)
%EVALUATESPEC Reduce a simulation run to the handful of numbers the spec cares about.
%
%   m = evaluateSpec(out, ds, P, meta)
%
%   Returns a struct of measured metrics plus a verdict for each spec item that
%   applies to this scenario. It measures and compares; it does not throw. The
%   caller decides what to do with a failure, which is what lets the same code
%   serve both the test suite and a plain report.
%
%   Why this is its own file rather than living inside the tests:
%   the moment "settling time" is implemented twice, the two implementations
%   drift, and you get a test that passes while the plot you show your
%   supervisor says otherwise. One definition, used everywhere.
%
%   Metrics (measured from meta.evalStart):
%     peakDeviation      largest |Vdc - Vdc_ref| in the window            [V]
%     overshoot          largest excursion PAST the final setpoint        [V]
%     settlingTime       time to enter and stay inside the tolerance band [s]
%     steadyStateError   |Vdc - Vdc_ref| at the final sample              [V]
%     maxCurrent         largest |i_out| over the whole run               [A]

arguments
    out
    ds
    P    struct
    meta struct
end

Vdc  = out.logsout.get("Vdc").Values;
iout = out.logsout.get("i_out").Values;

% The reference is an input, not a logged signal, so read it back from the
% dataset. Using the actual reference waveform (rather than the constant
% P.ctrl.Vdc_ref) is what makes these metrics correct for the reference_step
% scenario, where the setpoint itself moves.
%
% getElement returns a bare timeseries when the dataset was built from
% timeseries objects, but a Simulink.SimulationData.Signal wrapper when it came
% back from a simulation. Handle both rather than assuming one.
vrefTs = ds.getElement("Vdc_ref");
if ~isa(vrefTs, "timeseries")
    vrefTs = vrefTs.Values;
end
vref = interp1(vrefTs.Time, vrefTs.Data, Vdc.Time, "previous", "extrap");

t   = Vdc.Time;
err = abs(Vdc.Data - vref);

% Restrict to the evaluation window.
win     = t >= meta.evalStart;
tWin    = t(win);
errWin  = err(win);
VdcWin  = Vdc.Data(win);

m.peakDeviation    = max(errWin);
m.peakDeviationPct = 100 * m.peakDeviation / P.ctrl.Vdc_ref;
m.steadyStateError = err(end);
m.maxCurrent       = max(abs(iout.Data));

% --- Overshoot -------------------------------------------------------------
% Overshoot is how far the response goes PAST where it was heading, measured
% against the FINAL setpoint. That distinction matters: during a 700 -> 750 V
% reference step the tracking error momentarily reaches 50 V, but that is the
% commanded change, not overshoot. Overshoot is only whatever exceeds 750.
%
% When the setpoint does not move (a disturbance-rejection scenario) there is no
% approach direction, and any excursion in either direction counts.
%
% The direction test uses the tolerance band as a deadband rather than an exact
% comparison against zero. Without it, a bus sitting at 700.0000001 V instead of
% exactly 700 makes sign() return -1, the code then looks for an excursion BELOW
% the setpoint, finds none because the response goes up, and reports 0.00 V of
% overshoot on a run that clearly overshot. Comparing floating-point values for
% exact equality fails silently and in the flattering direction.
vrefFinal  = vref(end);
VdcAtStart = VdcWin(1);

if abs(vrefFinal - VdcAtStart) <= P.spec.VdcTolAbs
    direction = 0;                              % already at setpoint: disturbance
else
    direction = sign(vrefFinal - VdcAtStart);   % genuinely travelling somewhere
end

if direction == 0
    m.overshoot = max(abs(VdcWin - vrefFinal));
else
    m.overshoot = max(0, max(direction * (VdcWin - vrefFinal)));
end
m.overshootPct = 100 * m.overshoot / P.ctrl.Vdc_ref;

% --- Settling --------------------------------------------------------------
% Settling time is the LAST time the signal is outside the band, not the first
% time it enters. A response that dips into the band and then leaves again has
% not settled, and taking the first crossing would wrongly call it settled.
outsideBand = tWin(errWin > P.spec.VdcTolAbs);
if isempty(outsideBand)
    m.settlingTime = 0;
else
    m.settlingTime = max(outsideBand) - meta.evalStart;
end

% --- Verdicts --------------------------------------------------------------
% Only the spec items this scenario declared are evaluated. Anything else is
% reported as "not applicable" rather than silently passing, so a reader can
% tell the difference between "checked and fine" and "never checked".
settleLimit = P.spec.(meta.settleLimitField);

allChecks = struct( ...
    "overshoot",    struct(value = m.overshoot,        limit = P.spec.overshootAbs, units = "V"), ...
    "settling",     struct(value = m.settlingTime,     limit = settleLimit,         units = "s"), ...
    "steadyState",  struct(value = m.steadyStateError, limit = P.spec.VdcTolAbs,    units = "V"), ...
    "currentLimit", struct(value = m.maxCurrent,       limit = P.spec.ImaxAbs,      units = "A"));

names = string(fieldnames(allChecks))';
for name = names
    if ismember(name, meta.applies)
        c = allChecks.(name);
        m.checks.(name) = struct( ...
            applicable = true, ...
            value      = c.value, ...
            limit      = c.limit, ...
            units      = c.units, ...
            pass       = c.value <= c.limit);
    else
        m.checks.(name) = struct( ...
            applicable = false, ...
            value      = allChecks.(name).value, ...
            limit      = NaN, ...
            units      = allChecks.(name).units, ...
            pass       = true);
    end
end

m.allPass  = all(structfun(@(c) c.pass, m.checks));
m.applies  = meta.applies;
m.scenario = meta.scenario;
m.variant  = meta.variant;

% --- Traces ----------------------------------------------------------------
% Keep the exact signals the metrics were computed from, so a report plots what
% was measured rather than reconstructing it. Rebuilding the reference in the
% plotting code would create a second definition of "the setpoint", and the day
% those two disagree is the day a plot contradicts the number beside it.
if isequal(iout.Time, t)
    ioutOnT = iout.Data;
else
    ioutOnT = interp1(iout.Time, iout.Data, t, "previous", "extrap");
end
m.trace = struct(t = t, Vdc = Vdc.Data, vref = vref, iout = ioutOnT);
end
