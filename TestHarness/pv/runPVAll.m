function [results, metrics] = runPVAll(opts)
%RUNPVALL Run every PV scenario and print one verdict table.
%
%   runPVAll
%   runPVAll(Variant = "fastPO")
%   [results, metrics] = runPVAll();
%
%   Prints, per scenario, each spec item that applies with its measured value
%   and limit. Items the scenario did not declare print as "--" rather than as
%   a pass: "checked and fine" and "never checked" are different statements and
%   a report that conflates them is worse than no report.

arguments
    opts.Variant   (1,1) string  = "nominal"
    opts.Scenarios (1,:) string  = ["full_sun" "partial_600" "low_light_250" ...
                                    "cloud_step_down" "cloud_step_up" "cloud_ramp"]
end

scenarios = opts.Scenarios;
metrics   = cell(1, numel(scenarios));
P0        = pvParams(opts.Variant);

fprintf("\n");
fprintf("PV boost + P&O MPPT stage -- spec check [%s]\n", opts.Variant);
fprintf("source: Belal's PV/solarsimulink.slx    dD = %.3f / %.0f ms = %.2f duty/s\n", ...
        P0.ctrl.dD, P0.ctrl.Ts*1e3, P0.ctrl.slewRate);
fprintf("%s\n", repmat('=', 1, 96));
fprintf("%-17s %10s %10s %9s %9s %10s %9s   %s\n", ...
        "scenario", "track[%]", "reacq[s]", "rail[-]", "rip[%]", "busDev[V]", "Pmin[W]", "verdict");
fprintf("%s\n", repmat('-', 1, 96));

for k = 1:numel(scenarios)
    s = scenarios(k);
    [out, P, meta, ref] = runPVScenario(s, Variant = opts.Variant);
    m = evaluatePVSpec(out, P, meta, ref);
    metrics{k} = m;

    fprintf("%-17s %10s %10s %9s %9s %10s %9s   %s\n", s, ...
        cellFor(m, "tracking",  "%10.1f"), ...
        cellFor(m, "reacquire", "%10.3f"), ...
        cellFor(m, "dutyRail",  "%9.3f"),  ...
        cellFor(m, "ripple",    "%9.2f"),  ...
        cellFor(m, "busBand",   "%10.1f"), ...
        cellFor(m, "power",     "%9.0f"),  ...
        verdict(m));
end

fprintf("%s\n", repmat('-', 1, 96));

metrics = [metrics{:}];
results = summarise(metrics, P0);

nPass = sum([metrics.allPass]);
fprintf("%d of %d scenarios meet spec.\n\n", nPass, numel(metrics));

printFindings(metrics, P0);
end

% -----------------------------------------------------------------------------
function txt = cellFor(m, name, fmt)
%CELLFOR One metric, blanked when the scenario never checked it.
%   The alternative -- printing the measured number regardless -- puts a
%   plausible figure next to the word PASS for a requirement that was never
%   evaluated. Both halves are true and the combination is nonsense.
c = m.checks.(name);
if c.applicable
    txt = sprintf(fmt, c.value);
else
    txt = sprintf(regexprep(fmt, "\.\d+f", "s"), "--");
end
end

% -----------------------------------------------------------------------------
function v = verdict(m)
if m.allPass
    v = "PASS";
else
    failed = string(fieldnames(m.checks))';
    failed = failed(arrayfun(@(n) ~m.checks.(n).pass, failed));
    v = "FAIL: " + strjoin(failed, ", ");
end
if m.trackingWithdrawn
    v = v + "  (tracking withdrawn: reference is rail-limited)";
end
end

% -----------------------------------------------------------------------------
function results = summarise(metrics, P)
results = struct( ...
    variant   = P.ctrl.variant, ...
    slewRate  = P.ctrl.slewRate, ...
    nScenarios = numel(metrics), ...
    nPass     = sum([metrics.allPass]), ...
    scenarios = string({metrics.scenario}), ...
    allPass   = [metrics.allPass]);
end

% -----------------------------------------------------------------------------
function printFindings(metrics, P)
%PRINTFINDINGS Turn failures into sentences someone can act on.
%   A table says what failed. It does not say why, and "why" is the only part
%   that reaches the person who has to fix it.
lines = string.empty;

rail = metrics(arrayfun(@(m) ~m.checks.dutyRail.pass, metrics));
if ~isempty(rail)
    lines(end+1) = sprintf( ...
        "Duty saturates in: %s.\n" + ...
        "    A boost converter presents its source with R_in = R_load*(1-D)^2. The panel's\n" + ...
        "    own maximum-power resistance RISES as irradiance falls, so low light needs a LOW\n" + ...
        "    duty -- and duty stops at %.2f. With the load fixed at 98 ohm the operating point\n" + ...
        "    the panel wants is simply outside what this converter can present. No MPPT\n" + ...
        "    algorithm can fix that; it needs a load that is not a fixed resistor.", ...
        strjoin(string({rail.scenario}), ", "), P.ctrl.Dmin);
end

slow = metrics(arrayfun(@(m) ~m.checks.reacquire.pass, metrics));
if ~isempty(slow)
    worst = max([slow.reacquireTime]);
    lines(end+1) = sprintf( ...
        "Reacquisition too slow in: %s (worst %.2f s against a %.2f s limit).\n" + ...
        "    P&O moves duty by %.3f every %.0f ms, so the stage can slew %.2f duty per second\n" + ...
        "    and no faster. This is a rate limit, not a tuning error -- raising dD or\n" + ...
        "    shortening the perturbation period are the only levers.", ...
        strjoin(string({slow.scenario}), ", "), worst, P.spec.reacquireTime, ...
        P.ctrl.dD, P.ctrl.Ts*1e3, P.ctrl.slewRate);
end

bus = metrics(arrayfun(@(m) ~m.checks.busBand.pass, metrics));
if ~isempty(bus)
    lines(end+1) = sprintf( ...
        "DC bus outside %g +/- %g%% in: %s.\n" + ...
        "    The boost output feeds a fixed %g ohm resistor, so bus voltage is whatever the\n" + ...
        "    duty and the available power make it. Nothing regulates it. The integrated\n" + ...
        "    system holds this bus at %g V with the grid-side loop -- see\n" + ...
        "    config/harnessParams.m. Until this stage is tested against a stiff bus rather\n" + ...
        "    than a resistor, its MPPT behaviour here does not predict its behaviour there.", ...
        P.spec.busNom, P.spec.busTolPct, strjoin(string({bus.scenario}), ", "), ...
        98, P.spec.busNom);
end

rip = metrics(arrayfun(@(m) ~m.checks.ripple.pass, metrics));
if ~isempty(rip)
    lines(end+1) = sprintf( ...
        "Steady-state power ripple over %g%% in: %s.\n" + ...
        "    P&O dithers around the peak by construction; the size of the dither is set by\n" + ...
        "    dD = %.3f. Reducing it lowers ripple and slows reacquisition -- the two specs\n" + ...
        "    pull in opposite directions and dD is the single knob between them.", ...
        P.spec.powerRipplePct, strjoin(string({rip.scenario}), ", "), P.ctrl.dD);
end

if isempty(lines)
    fprintf("No findings: every applicable requirement was met.\n\n");
    return
end

fprintf("FINDINGS\n%s\n", repmat('-', 1, 96));
for k = 1:numel(lines)
    fprintf("%d.  %s\n\n", k, lines(k));
end
end
