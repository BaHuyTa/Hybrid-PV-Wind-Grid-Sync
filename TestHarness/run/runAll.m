function summary = runAll(opts)
%RUNALL Run every scenario, print a spec-compliance report, check for regressions.
%
%   summary = runAll()
%   summary = runAll(Variant = "sluggish")
%   summary = runAll(SaveBaseline = true)      % record today's run as the reference
%   summary = runAll(LogToSDI = false)         % skip the Simulation Data Inspector
%   summary = runAll(Report = true)            % also write a standalone HTML report
%
%   This is the one-button entry point. It is what you run before showing
%   anything to a supervisor, and what you run after anyone changes anything.
%
%   Returns a table with one row per scenario.
%
%   Name-value arguments:
%     Variant          "nominal" (default) or "sluggish"
%     LogToSDI         true (default). Push each run to the Simulation Data
%                      Inspector so runs can be compared visually later.
%     SaveBaseline     false (default). When true, overwrite the stored baseline
%                      with this run. Do this deliberately, never casually --
%                      saving a baseline blesses the current behaviour as
%                      correct, and a baseline saved from a broken run makes
%                      every future regression check agree with the breakage.
%     CompareBaseline  true (default). Compare against the stored baseline and
%                      report any metric that has moved.
%     Report           false (default). When true, write a self-contained HTML
%                      report to results/reports/ with a plot per scenario.
%                      Off by default because rendering figures costs a few
%                      seconds, and the console table is the right tool for the
%                      edit-run-check loop. Turn it on when the result is going
%                      to somebody else.

arguments
    opts.Variant         (1,1) string  = "nominal"
    opts.LogToSDI        (1,1) logical = true
    opts.SaveBaseline    (1,1) logical = false
    opts.CompareBaseline (1,1) logical = true
    opts.Report          (1,1) logical = false
end

scenarios = ["source_step", "source_ramp", "cloud_transient", ...
             "reference_step", "cold_start", "overload"];

root         = fileparts(fileparts(mfilename("fullpath")));
baselineFile = fullfile(root, "results", "baseline", ...
                        "baseline_" + opts.Variant + ".mat");

if opts.LogToSDI
    Simulink.sdi.clear;   % start from a clean slate so the run list is readable
end

rows = table.empty(0, 7);
metricsStore = struct();
reportData   = cell(1, numel(scenarios));

fprintf("\n=== DC-link loop, %s controller =====================================\n", ...
        opts.Variant);
fprintf("%-17s %10s %10s %10s %10s   %s\n", ...
        "scenario", "over(V)", "settle(s)", "sse(V)", "imax(A)", "verdict");
fprintf("%s\n", repmat('-', 1, 78));

for k = 1:numel(scenarios)
    s = scenarios(k);
    [out, P, meta, ds] = runScenario(s, Variant = opts.Variant, ...
                                        LogToSDI = opts.LogToSDI);
    m = evaluateSpec(out, ds, P, meta);

    verdict = formatVerdict(m);

    % Print a dash, not a number, in any column this scenario never checked.
    % See metricCell below for why that matters.
    [overTxt, overVal] = metricCell(m, "overshoot",    "%.2f");
    [setTxt,  setVal]  = metricCell(m, "settling",     "%.4f");
    [sseTxt,  sseVal]  = metricCell(m, "steadyState",  "%.2f");
    [imaxTxt, imaxVal] = metricCell(m, "currentLimit", "%.2f");

    fprintf("%-17s %10s %10s %10s %10s   %s\n", ...
            s, overTxt, setTxt, sseTxt, imaxTxt, verdict);

    rows = [rows; {s, overVal, setVal, sseVal, imaxVal, ...
                   m.allPass, verdict}]; %#ok<AGROW>

    reportData{k} = struct(scenario = s, metrics = m, meta = meta, ...
                           verdict = verdict);

    % Store the metrics plus the Vdc trace. Metrics catch a spec regression;
    % the trace catches a change in shape that happens to leave the headline
    % numbers alone.
    metricsStore.(s) = struct( ...
        overshoot        = m.overshoot, ...
        settlingTime     = m.settlingTime, ...
        steadyStateError = m.steadyStateError, ...
        maxCurrent       = m.maxCurrent, ...
        VdcTime          = out.logsout.get("Vdc").Values.Time, ...
        VdcData          = out.logsout.get("Vdc").Values.Data);
end

rows.Properties.VariableNames = ["scenario", "overshoot_V", "settling_s", ...
                                 "steadyStateError_V", "maxCurrent_A", ...
                                 "pass", "verdict"];
summary = rows;

% Every scenario produced the same set of fields, so this collapses to a plain
% struct array. Built as a cell first because assigning into an empty struct
% array fails until it knows what fields to expect.
reportData = [reportData{:}];

fprintf("%s\n", repmat('-', 1, 78));
nPass = nnz(summary.pass);
fprintf("%d of %d scenarios meet every requirement that applies to them.\n", ...
        nPass, height(summary));

if opts.LogToSDI
    fprintf("Runs recorded in the Simulation Data Inspector. Open with: Simulink.sdi.view\n");
end

%% Regression check ----------------------------------------------------------
regression = struct(ran = false, anyDrift = false, ...
                    savedOn = NaT, lines = strings(0));

if opts.CompareBaseline && isfile(baselineFile) && ~opts.SaveBaseline
    regression = compareToBaseline(metricsStore, baselineFile, scenarios);
elseif opts.CompareBaseline && ~isfile(baselineFile) && ~opts.SaveBaseline
    fprintf("\nNo baseline stored yet for the %s variant.\n", opts.Variant);
    fprintf("Once you are satisfied this run is correct, record it with:\n");
    fprintf("    runAll(Variant = ""%s"", SaveBaseline = true)\n", opts.Variant);
end

if opts.SaveBaseline
    baseline = struct(metrics = metricsStore, ...
                      savedOn = datetime("now"), ...
                      variant = opts.Variant);
    if ~isfolder(fileparts(baselineFile))
        mkdir(fileparts(baselineFile));
    end
    save(baselineFile, "-struct", "baseline");
    fprintf("\nBaseline saved: %s\n", baselineFile);
    fprintf("Future runs will be compared against this. If it was wrong, delete it.\n");
end

%% Report --------------------------------------------------------------------
if opts.Report
    reportFile = generateReport(reportData, P, summary, regression, ...
                               Variant = opts.Variant, Root = root);
    fprintf("\nReport written: %s\n", reportFile);
end

fprintf("\n");
end

% -----------------------------------------------------------------------------
function [txt, val] = metricCell(m, checkName, fmt)
%METRICCELL Format one metric, blanking it when the scenario never checked it.
%
%   A number printed under a column heading invites the reader to judge it
%   against that heading's limit. When the scenario never checked that
%   requirement, the number is a true measurement of something nobody asked
%   about, and printing it is misleading.
%
%   The overload scenario is the case that forced this. It deliberately drives
%   the bus past what the inverter can hold, so regulation is EXPECTED to be
%   lost -- the only requirement that applies is the current limit. But the
%   overshoot and steady-state columns still had real arithmetic in them, and
%   printed "4563.22" next to the word PASS. Both halves were true and the
%   combination was nonsense. A reader either distrusts the whole table or,
%   worse, believes it.
%
%   The dash says "not checked here" out loud. In the returned table the same
%   cell is NaN, which is how MATLAB spells "not applicable" in a numeric
%   column and keeps mean/max over that column honest.
if m.checks.(checkName).applicable
    val = m.checks.(checkName).value;
    txt = sprintf(fmt, val);
else
    val = NaN;
    txt = "--";
end
end

% -----------------------------------------------------------------------------
function verdict = formatVerdict(m)
%FORMATVERDICT Name the failing checks, or say which were skipped and why.
names  = string(fieldnames(m.checks))';
failed = strings(0);
for n = names
    c = m.checks.(n);
    if c.applicable && ~c.pass
        failed(end+1) = n; %#ok<AGROW>
    end
end

skipped = setdiff(names, m.applies);

if ~isempty(failed)
    verdict = "FAIL: " + strjoin(failed, ", ");
elseif ~isempty(skipped)
    % Say so out loud. "PASS" on a scenario where three of four checks were
    % never run is misleading unless the report admits it.
    verdict = "pass (only " + strjoin(m.applies, ", ") + " applies)";
else
    verdict = "PASS";
end
end

% -----------------------------------------------------------------------------
function regression = compareToBaseline(current, baselineFile, scenarios)
%COMPARETOBASELINE Report any metric that has moved since the baseline was saved.
%
%   The tolerances below are not "how much error is acceptable" -- the spec
%   already covers that. They are "how much change is worth telling a human
%   about". A model that still passes the spec but whose settling time doubled
%   has changed in a way somebody should know about before it surprises them.
%
%   Returns what it found as well as printing it, so the HTML report can carry
%   the same result without running the comparison a second time.
b = load(baselineFile);

tol.overshoot        = 0.5;      % V
tol.settlingTime     = 0.005;    % s
tol.steadyStateError = 0.5;      % V
tol.maxCurrent       = 0.1;      % A
waveformTol          = 1.0;      % V, largest allowed point-by-point change

fprintf("\n--- Regression check against baseline saved %s ---\n", ...
        string(b.savedOn, "yyyy-MM-dd HH:mm"));

% Findings are collected first and printed afterwards. Every finding therefore
% exists as text exactly once, which is what lets the console and the HTML
% report say the same thing without the comparison running twice.
lines = strings(0);
metricNames = ["overshoot", "settlingTime", "steadyStateError", "maxCurrent"];

for s = scenarios
    if ~isfield(b.metrics, s)
        lines(end+1) = sprintf("%-17s new scenario, not in baseline", s); %#ok<AGROW>
        continue
    end
    old = b.metrics.(s);
    new = current.(s);

    for mn = metricNames
        delta = new.(mn) - old.(mn);
        if abs(delta) > tol.(mn)
            lines(end+1) = sprintf("%-17s %-17s %8.4f -> %8.4f  (%+.4f)", ...
                 s, mn, old.(mn), new.(mn), delta); %#ok<AGROW>
        end
    end

    % Waveform comparison. Only meaningful because the model runs on a fixed
    % step, so both runs land on identical sample times.
    if isequal(size(old.VdcData), size(new.VdcData))
        maxDiff = max(abs(new.VdcData - old.VdcData));
        if maxDiff > waveformTol
            lines(end+1) = sprintf("%-17s %-17s max point difference %.3f V", ...
                 s, "Vdc waveform", maxDiff); %#ok<AGROW>
        end
    else
        lines(end+1) = sprintf("%-17s %-17s length changed %d -> %d samples", ...
             s, "Vdc waveform", numel(old.VdcData), numel(new.VdcData)); %#ok<AGROW>
    end
end

anyDrift = ~isempty(lines);
for k = 1:numel(lines)
    fprintf("  %s\n", lines(k));
end

if ~anyDrift
    fprintf("  No drift. Every metric and waveform matches the baseline.\n");
else
    fprintf("\n  Something moved. If the change was intended, re-record with:\n");
    fprintf("      runAll(SaveBaseline = true)\n");
end

regression = struct(ran = true, anyDrift = anyDrift, ...
                    savedOn = b.savedOn, lines = lines);
end
