function m = evaluatePVSpec(out, P, meta, ref)
%EVALUATEPVSPEC Reduce a PV-stage run to the numbers the spec cares about.
%
%   m = evaluatePVSpec(out, P, meta, ref)
%
%   Measures and compares; never throws. The caller decides what a failure
%   means, which is what lets the same code serve both the test suite and a
%   plain report. One definition of "tracking efficiency", used everywhere --
%   the moment it is implemented twice, the two drift, and you get a test that
%   passes while the plot you show your supervisor says otherwise.
%
%   Metrics:
%     trackingEffPct     captured power as % of the swept maximum          [%]
%     reacquireTime      time after the irradiance change to re-enter band [s]
%     railClearance      smallest distance from duty to either rail        [-]
%     powerRipplePct     peak-to-peak dither in mean power                 [%]
%     busPeakDev         largest |Vdc - 700| in the steady window          [V]
%     minPanelPower      lowest panel power after start-up                 [W]

arguments
    out
    P    struct
    meta struct
    ref  struct
end

L    = out.logsout;
V    = L.getElement("V").Values;
I    = L.getElement("I").Values;
Vdc  = L.getElement("Vdc").Values;
Duty = L.getElement("Duty").Values;

t   = V.Time;
Ppv = V.Data .* I.Data;

% The MPPT dither is what the ripple spec is about, and it lives at 100 Hz (one
% perturbation per 10 ms). Underneath it sits 10 kHz switching ripple, which is
% a property of the converter, not the algorithm. Averaging over one
% perturbation period separates them; without it the two are added together and
% the algorithm gets blamed for the switch.
Pfilt = movmean(Ppv, P.ctrl.Ts, SamplePoints = t);

% Reacquisition is a question about the TREND, and it needs a slower average
% than ripple does. Measured on Pfilt, a stage whose steady dither is larger
% than the tracking band never counts as settled: every few perturbations it
% dips back out, so "the last time it was outside the band" keeps advancing and
% ends up reporting roughly the length of the run.
%
% That is not a hypothetical. The fastPO variant on cloud_ramp measured 1.77 s
% this way while the trend had actually arrived in 0.27 s -- the extra 1.5 s was
% its own 2.7 % dither crossing a 2 % band. Worse, the number was plausible
% enough to be believed, and it pointed at the wrong root cause: it looked like
% the fix had made reacquisition worse when what it had really done was trade
% reacquisition for ripple. Averaging over ten perturbations separates the two
% so each spec item answers its own question.
Ptrend = movmean(Ppv, P.ctrl.trendPeriods * P.ctrl.Ts, SamplePoints = t);

% Duty is sampled at 10 ms and everything else at solver steps, so the two
% cannot be indexed against each other. Hold-interpolate rather than resample:
% duty IS a held value between perturbations, so "previous" is the true
% waveform, not an approximation of it.
DutyOnT = interp1(Duty.Time, Duty.Data, t, "previous", "extrap");

band = P.spec.trackingEffPct / 100 * ref.Pmax;

%% --- Reacquisition --------------------------------------------------------
% Measured as the LAST time the stage was outside the tracking band, not the
% first time it entered. A response that dips back out after briefly touching
% the band has not reacquired, and taking the first crossing would call it
% settled while it was still hunting.
m.reacquireTruncated = false;
if isnan(meta.event)
    m.reacquireTime = 0;          % nothing to reacquire from
    settledAt       = meta.evalStart;
else
    after   = t >= meta.event;
    tAfter  = t(after);
    outside = tAfter(Ptrend(after) < band);
    if isempty(outside)
        m.reacquireTime = 0;
        settledAt       = meta.event;
    else
        m.reacquireTime      = max(outside) - meta.event;
        settledAt            = max(outside);
        % Still hunting when the run ended: the number is a lower bound, so say
        % so rather than reporting it as if it were a result.
        m.reacquireTruncated = settledAt >= t(end) - 10*P.ctrl.Ts;
    end
end

%% --- The steady-state window ----------------------------------------------
% Steady-state metrics are measured from whichever is LATER: the nominal
% evaluation start for this scenario, or the moment the stage actually finished
% reacquiring. That second term is not bookkeeping.
%
% Without it, a slow reacquisition leaks into the ripple number: the tail of the
% hunt gets averaged in as though it were dither, and the run reports a ripple
% failure ON TOP OF the reacquire failure. Two failures, one root cause -- and
% the reader has no way to tell that fixing the first would erase the second.
% Measured this way, each requirement fails for its own reason or not at all.
guard      = 5 * P.ctrl.Ts;
steadyFrom = max(meta.evalStart, settledAt + guard);
win        = t >= steadyFrom;

% If the run ended before a steady window opened there is nothing to measure,
% and the honest answer is "not measured" rather than a number computed from a
% transient. The steady-state checks are withdrawn below.
m.steadyFrom     = steadyFrom;
m.steadyDuration = max(0, t(end) - steadyFrom);
m.steadyUsable   = m.steadyDuration >= 20 * P.ctrl.Ts;

if ~m.steadyUsable
    win = t >= max(meta.evalStart, t(end) - 20*P.ctrl.Ts);   % something to report
end

PfiltW = Pfilt(win);
VdcW   = Vdc.Data(win);
DutyW  = DutyOnT(win);

%% --- Tracking efficiency --------------------------------------------------
m.meanPower      = mean(PfiltW);
m.refPower       = ref.Pmax;
m.trackingEffPct = 100 * m.meanPower / ref.Pmax;
m.refReachable   = ref.reachable;
m.refDuty        = ref.Dmpp;

%% --- Duty rails -----------------------------------------------------------
m.dutyMin       = min(DutyW);
m.dutyMax       = max(DutyW);
m.railClearance = min(m.dutyMin - P.ctrl.Dmin, P.ctrl.Dmax - m.dutyMax);

%% --- Steady-state ripple --------------------------------------------------
m.powerRipplePct = 100 * (max(PfiltW) - min(PfiltW)) / mean(PfiltW);

%% --- DC-link interface ----------------------------------------------------
m.busMean    = mean(VdcW);
m.busMin     = min(VdcW);
m.busMax     = max(VdcW);
m.busPeakDev = max(abs(VdcW - P.spec.busNom));

%% --- Reverse power --------------------------------------------------------
% Continuous, not steady-state: a reverse-power event during a transient is
% still a defect. Measured from the end of start-up blanking rather than from
% t = 0, because the Simscape solver brings the bus up from zero over the first
% few milliseconds and calling that a fault would fail every run.
afterStart      = t >= P.sim.startupBlank;
m.minPanelPower = min(Pfilt(afterStart));

%% --- Verdicts -------------------------------------------------------------
% Only the spec items this scenario declared are evaluated. Everything else is
% reported as not-applicable rather than silently passing, so a reader can tell
% "checked and fine" from "never checked".
%
% dir is which way the comparison runs. Getting it wrong is a quiet disaster: a
% tracking efficiency compared with <= would pass at 3 %.
allChecks = struct( ...
  "tracking",  struct(value=m.trackingEffPct, limit=P.spec.trackingEffPct,  units="%", dir="min"), ...
  "reacquire", struct(value=m.reacquireTime,  limit=P.spec.reacquireTime,   units="s", dir="max"), ...
  "dutyRail",  struct(value=m.railClearance,  limit=P.spec.dutyRailMargin,  units="",  dir="min"), ...
  "ripple",    struct(value=m.powerRipplePct, limit=P.spec.powerRipplePct,  units="%", dir="max"), ...
  "busBand",   struct(value=m.busPeakDev,     limit=P.spec.busNom*P.spec.busTolPct/100, units="V", dir="max"), ...
  "power",     struct(value=m.minPanelPower,  limit=P.spec.minPanelPower,   units="W", dir="min"));

steadyChecks = ["tracking" "dutyRail" "ripple" "busBand"];

names = string(fieldnames(allChecks))';
for name = names
    c = allChecks.(name);
    if c.dir == "min"
        passed = c.value >= c.limit;
    else
        passed = c.value <= c.limit;
    end
    applicable = ismember(name, meta.applies);

    % No steady window means no steady-state measurement.
    if applicable && ~m.steadyUsable && ismember(name, steadyChecks)
        applicable = false;
    end

    m.checks.(name) = struct( ...
        applicable = applicable, ...
        value      = c.value, ...
        limit      = ternary(applicable, c.limit, NaN), ...
        units      = c.units, ...
        dir        = c.dir, ...
        pass       = ~applicable || passed);
end

% Tracking efficiency measured against a rail-limited ceiling is not a
% meaningful number: a saturated controller scores 100 % against a saturated
% reference. Rather than report a flattering pass, the check is withdrawn and
% dutyRail is left to carry the finding. Silently passing here would hide the
% single most important thing this harness has to say.
m.trackingWithdrawn = ~ref.reachable && m.checks.tracking.applicable;
if m.trackingWithdrawn
    m.checks.tracking.applicable = false;
    m.checks.tracking.limit      = NaN;
    m.checks.tracking.pass       = true;
end

m.allPass  = all(structfun(@(c) c.pass, m.checks));
m.applies  = meta.applies;
m.scenario = meta.scenario;
m.variant  = meta.variant;

%% --- Traces ---------------------------------------------------------------
% The exact signals the metrics came from, so a report plots what was measured.
m.trace = struct(t = t, Ppv = Ppv, Pfilt = Pfilt, Vpv = V.Data, ...
                 Vdc = Vdc.Data, Duty = DutyOnT, refP = ref.Pmax, ...
                 band = band, steadyFrom = steadyFrom);
end

% -----------------------------------------------------------------------------
function v = ternary(c, a, b)
if c; v = a; else; v = b; end
end
