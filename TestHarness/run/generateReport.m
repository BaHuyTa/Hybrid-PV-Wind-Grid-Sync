function reportFile = generateReport(reportData, P, summary, regression, opts)
%GENERATEREPORT Write a standalone HTML report of a harness run.
%
%   reportFile = generateReport(reportData, P, summary, regression, ...)
%
%   Normally reached through runAll(Report = true) rather than called directly.
%
%   The output is ONE file with the figures embedded inside it as base64 PNGs.
%   No image folder, no stylesheet, no toolbox needed to open it. You can email
%   it, drop it in a report appendix, or hand it to a teammate who does not have
%   MATLAB, and it still renders.
%
%   Why not MATLAB Report Generator, which is licensed here and is the "proper"
%   answer? Because its output is a document that assumes a toolchain: the
%   template, the DOM API, and a reader who can regenerate it. That is the right
%   trade for a company with a document standard to meet. For a project
%   deliverable that mostly needs to survive being emailed, a self-contained
%   file wins. If this later has to match a company template or produce Word or
%   PDF, switch to mlreportgen.dom -- the data assembled here is what it would
%   consume anyway.
%
%   Name-value arguments:
%     Variant   which parameter set produced this run, for the header
%     Root      TestHarness root folder; the report lands in <Root>/results/reports

arguments
    reportData struct
    P          struct
    summary    table
    regression struct
    opts.Variant (1,1) string = "nominal"
    opts.Root    (1,1) string = string(fileparts(fileparts(mfilename("fullpath"))))
end

stamp     = datetime("now");
outDir    = fullfile(opts.Root, "results", "reports");
if ~isfolder(outDir)
    mkdir(outDir);
end
reportFile = fullfile(outDir, ...
    "report_" + opts.Variant + "_" + string(stamp, "yyyyMMdd_HHmmss") + ".html");

nPass = nnz(summary.pass);
nTot  = height(summary);

%% Assemble ------------------------------------------------------------------
h = strings(0);
h(end+1) = htmlHead(opts.Variant, stamp, nPass, nTot);
h(end+1) = summaryTable(reportData);

for k = 1:numel(reportData)
    h(end+1) = scenarioSection(reportData(k), P); %#ok<AGROW>
end

h(end+1) = regressionSection(regression);
h(end+1) = htmlFoot(opts.Variant, P);

%% Write ---------------------------------------------------------------------
% Explicit UTF-8. The default encoding on a Windows machine is not, and a
% report that renders mojibake on somebody else's computer is not a deliverable.
fid = fopen(reportFile, "w", "n", "UTF-8");
if fid < 0
    error("generateReport:cannotWrite", "Could not open %s for writing.", reportFile);
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, "%s", strjoin(h, newline));
end

% =============================================================================
function s = htmlHead(variant, stamp, nPass, nTot)
%HTMLHEAD Document head, styles, and the banner.
%
%   The theme is pinned light rather than following prefers-color-scheme. This
%   file gets opened on whatever machine happens to have it, and half of those
%   are set to dark mode -- a report that inverts itself depending on the
%   reader's OS is not a report you can point at in a meeting. It also has to
%   print, and printing a dark theme wastes toner and reads badly.

if nPass == nTot
    bannerClass = "ok";
    bannerText  = sprintf("%d of %d scenarios meet every requirement that applies to them.", ...
                          nPass, nTot);
else
    bannerClass = "bad";
    bannerText  = sprintf("%d of %d scenarios pass. %d need attention.", ...
                          nPass, nTot, nTot - nPass);
end

s = "<!doctype html>" + newline + ...
"<html lang=""en"" data-theme=""light"">" + newline + ...
"<head>" + newline + ...
"<meta charset=""utf-8"">" + newline + ...
"<meta name=""viewport"" content=""width=device-width, initial-scale=1"">" + newline + ...
"<title>DC-link loop test report &middot; " + esc(variant) + "</title>" + newline + ...
"<style>" + newline + ...
":root{" + newline + ...
"  --paper:#FCFCFA; --panel:#FFFFFF; --sunken:#F1F2EC;" + newline + ...
"  --ink:#232621; --ink-soft:#5A6055; --ink-faint:#7C8276;" + newline + ...
"  --line:#E5E7DE; --line-strong:#CBCEC0;" + newline + ...
"  --blueprint:#1F5FA8; --copper:#B8672A; --teal:#1E7A63; --danger:#B23434;" + newline + ...
"}" + newline + ...
"*{box-sizing:border-box;}" + newline + ...
"body{margin:0;padding:0 0 4rem;background:var(--paper);color:var(--ink);" + newline + ...
"  font-family:""IBM Plex Sans"",""Segoe UI"",system-ui,sans-serif;line-height:1.55;}" + newline + ...
".wrap{max-width:60rem;margin:0 auto;padding:0 1.5rem;}" + newline + ...
"header{border-bottom:2px solid var(--line-strong);padding:2.5rem 0 1.25rem;margin-bottom:1.5rem;}" + newline + ...
"h1{font-size:1.6rem;margin:0 0 .35rem;letter-spacing:-.01em;}" + newline + ...
".sub{color:var(--ink-soft);font-size:.9rem;margin:0;}" + newline + ...
".sub code{background:var(--sunken);padding:.1rem .35rem;border-radius:3px;" + newline + ...
"  font-family:""IBM Plex Mono"",ui-monospace,Consolas,monospace;font-size:.85em;}" + newline + ...
".banner{margin:1.25rem 0 2rem;padding:.75rem 1rem;border-radius:4px;font-weight:600;" + newline + ...
"  border-left:4px solid;}" + newline + ...
".banner.ok{background:#EFF6F2;border-color:var(--teal);color:#155A49;}" + newline + ...
".banner.bad{background:#FBF0F0;border-color:var(--danger);color:#8A2727;}" + newline + ...
"h2{font-size:1.05rem;margin:2.5rem 0 .75rem;padding-bottom:.35rem;" + newline + ...
"  border-bottom:1px solid var(--line);letter-spacing:.01em;}" + newline + ...
"table{border-collapse:collapse;width:100%;font-size:.85rem;margin:.5rem 0 1rem;}" + newline + ...
"th,td{text-align:right;padding:.4rem .6rem;border-bottom:1px solid var(--line);}" + newline + ...
"th:first-child,td:first-child{text-align:left;}" + newline + ...
"th{font-weight:600;color:var(--ink-soft);font-size:.75rem;text-transform:uppercase;" + newline + ...
"  letter-spacing:.04em;border-bottom:1px solid var(--line-strong);}" + newline + ...
"td.num{font-family:""IBM Plex Mono"",ui-monospace,Consolas,monospace;font-variant-numeric:tabular-nums;}" + newline + ...
"td.na{color:var(--ink-faint);}" + newline + ...
".chip{display:inline-block;padding:.1rem .5rem;border-radius:99px;font-size:.72rem;" + newline + ...
"  font-weight:600;letter-spacing:.03em;}" + newline + ...
".chip.pass{background:#E4F0EA;color:#155A49;}" + newline + ...
".chip.fail{background:#F7E3E3;color:#8A2727;}" + newline + ...
".chip.partial{background:#F5EAE0;color:#8A4A18;}" + newline + ...
".card{background:var(--panel);border:1px solid var(--line);border-radius:6px;" + newline + ...
"  padding:1.25rem 1.5rem;margin:1rem 0 2rem;}" + newline + ...
".card h3{margin:0 0 .25rem;font-size:1rem;font-family:""IBM Plex Mono"",ui-monospace,Consolas,monospace;}" + newline + ...
".card .desc{color:var(--ink-soft);font-size:.85rem;margin:.35rem 0 1rem;}" + newline + ...
".card img{width:100%;height:auto;display:block;margin-top:1rem;" + newline + ...
"  border:1px solid var(--line);border-radius:4px;}" + newline + ...
".note{color:var(--ink-faint);font-size:.8rem;font-style:italic;margin:.5rem 0 0;}" + newline + ...
"pre{background:var(--sunken);border:1px solid var(--line);border-radius:4px;" + newline + ...
"  padding:.75rem 1rem;overflow-x:auto;font-size:.8rem;" + newline + ...
"  font-family:""IBM Plex Mono"",ui-monospace,Consolas,monospace;}" + newline + ...
"footer{margin-top:3rem;padding-top:1rem;border-top:1px solid var(--line);" + newline + ...
"  color:var(--ink-faint);font-size:.78rem;}" + newline + ...
"@media print{body{background:#fff;} .card{break-inside:avoid;page-break-inside:avoid;}}" + newline + ...
"</style>" + newline + ...
"</head>" + newline + ...
"<body><div class=""wrap"">" + newline + ...
"<header>" + newline + ...
"<h1>DC-link voltage loop &mdash; test report</h1>" + newline + ...
"<p class=""sub"">Model <code>DCLinkLoop.slx</code> &nbsp;&middot;&nbsp; parameter set <code>" + ...
   esc(variant) + "</code> &nbsp;&middot;&nbsp; generated " + ...
   esc(string(stamp, "d MMM yyyy, HH:mm")) + " &nbsp;&middot;&nbsp; MATLAB " + ...
   esc(string(version("-release"))) + "</p>" + newline + ...
"</header>" + newline + ...
"<div class=""banner " + bannerClass + """>" + esc(bannerText) + "</div>";
end

% =============================================================================
function s = summaryTable(reportData)
%SUMMARYTABLE One row per scenario, measured value against its limit.
%
%   Columns a scenario does not check show a dash, never a number. The console
%   table follows the same rule; see metricCell in runAll.m for the reasoning.

rows = strings(0);
for k = 1:numel(reportData)
    d = reportData(k);
    m = d.metrics;
    rows(end+1) = "<tr><td>" + esc(d.scenario) + "</td>" + ...
        metricTd(m, "overshoot", "%.2f") + ...
        metricTd(m, "settling", "%.4f") + ...
        metricTd(m, "steadyState", "%.2f") + ...
        metricTd(m, "currentLimit", "%.2f") + ...
        "<td>" + verdictChip(m) + "</td></tr>"; %#ok<AGROW>
end

s = "<h2>Summary</h2>" + newline + ...
"<table>" + newline + ...
"<thead><tr><th>Scenario</th><th>Overshoot (V)</th><th>Settling (s)</th>" + ...
"<th>Steady-state err (V)</th><th>Peak current (A)</th><th>Verdict</th></tr></thead>" + newline + ...
"<tbody>" + strjoin(rows, newline) + "</tbody>" + newline + "</table>" + newline + ...
"<p class=""note"">A dash means the scenario does not check that requirement, " + ...
"so no number is shown. Limits are listed per scenario below.</p>";
end

% =============================================================================
function s = scenarioSection(d, P)
%SCENARIOSECTION One card per scenario: what it checks, what it measured, the plot.
m = d.metrics;

% Per-check table, applicable checks only. An inapplicable check has no limit,
% so there is nothing to compare and nothing worth a row.
rows = strings(0);
names = string(fieldnames(m.checks))';
for n = names
    c = m.checks.(n);
    if ~c.applicable
        continue
    end
    if c.pass
        chip = "<span class=""chip pass"">PASS</span>";
    else
        chip = "<span class=""chip fail"">FAIL</span>";
    end
    margin = 100 * (1 - c.value / c.limit);
    rows(end+1) = sprintf( ...
        "<tr><td>%s</td><td class=""num"">%.4f %s</td><td class=""num"">%.4f %s</td>" + ...
        "<td class=""num"">%+.0f%%</td><td>%s</td></tr>", ...
        esc(n), c.value, esc(c.units), c.limit, esc(c.units), margin, chip); %#ok<AGROW>
end

skipped = setdiff(names, string(m.applies));
if isempty(skipped)
    skipNote = "";
else
    skipNote = "<p class=""note"">Not checked here: " + ...
               esc(strjoin(skipped, ", ")) + ".</p>";
end

if isfield(d.meta, "description")
    desc = "<p class=""desc"">" + esc(string(d.meta.description)) + "</p>";
else
    desc = "";
end

s = "<div class=""card"">" + newline + ...
    "<h3>" + esc(d.scenario) + " &nbsp;" + verdictChip(m) + "</h3>" + newline + ...
    desc + newline + ...
    "<table><thead><tr><th>Requirement</th><th>Measured</th><th>Limit</th>" + ...
    "<th>Margin</th><th></th></tr></thead><tbody>" + newline + ...
    strjoin(rows, newline) + newline + "</tbody></table>" + newline + ...
    skipNote + newline + ...
    "<img alt=""" + esc(d.scenario) + " response"" src=""" + embedFigure(d, P) + """>" + newline + ...
    "</div>";
end

% =============================================================================
function s = regressionSection(r)
%REGRESSIONSECTION What moved since the baseline, if the check ran at all.
%
%   "Did not run" is reported as its own state. A report that silently omits
%   the regression section reads as "no drift" to anyone skimming it, which is
%   the opposite of what an absent check means.
if ~r.ran
    s = "<h2>Regression check</h2>" + newline + ...
        "<p class=""note"">Not run for this report. No stored baseline, or the " + ...
        "baseline was being re-recorded.</p>";
    return
end

if r.anyDrift
    body = "<pre>" + esc(strjoin(r.lines, newline)) + "</pre>" + newline + ...
           "<p class=""note"">These metrics moved by more than the reporting " + ...
           "tolerance. Passing the spec and matching the baseline are different " + ...
           "questions &mdash; a run can do the first and fail the second.</p>";
else
    body = "<div class=""banner ok"">No drift. Every metric and waveform matches " + ...
           "the baseline.</div>";
end

s = "<h2>Regression check</h2>" + newline + ...
    "<p class=""sub"">Against baseline recorded " + ...
    esc(string(r.savedOn, "d MMM yyyy, HH:mm")) + ".</p>" + newline + body;
end

% =============================================================================
function s = htmlFoot(variant, P)
%HTMLFOOT How to reproduce this exact report.
s = "<footer>" + newline + ...
"<p>Generated by <code>runAll(Variant = &quot;" + esc(variant) + "&quot;, Report = true)</code>. " + ...
"Spec limits: " + sprintf("%.0f%% overshoot, %.0f ms settling, %.0f%% tolerance band, %.1f A current limit", ...
    P.spec.overshootPct, P.spec.settleTime*1000, P.spec.VdcTolPct, P.spec.ImaxAbs) + ". " + ...
"All limits come from <code>config/harnessParams.m</code>; nothing in this report was typed by hand.</p>" + newline + ...
"</footer>" + newline + "</div></body></html>";
end

% =============================================================================
function uri = embedFigure(d, P)
%EMBEDFIGURE Render the scenario response and return it as a base64 data URI.
%
%   Rendered off-screen and deleted immediately. The PNG never touches the
%   project folder -- it lives inside the HTML file, which is the whole point of
%   a single-file report.
tr = d.metrics.trace;

fig = figure(Visible = "off", Color = "w", Position = [100 100 980 560]);
cleanupFig = onCleanup(@() close(fig));

tl = tiledlayout(fig, 2, 1, TileSpacing = "compact", Padding = "compact");

blueprint = [0.122 0.373 0.659];
copper    = [0.722 0.404 0.165];
teal      = [0.118 0.478 0.388];
danger    = [0.698 0.204 0.204];

% --- Bus voltage ---------------------------------------------------------
ax1 = nexttile(tl);
hold(ax1, "on");
band = P.spec.VdcTolAbs;
fill(ax1, [tr.t; flipud(tr.t)], [tr.vref + band; flipud(tr.vref - band)], ...
     [0.88 0.94 0.91], EdgeColor = "none", ...
     DisplayName = sprintf("±%.0f V tolerance band", band));
plot(ax1, tr.t, tr.vref, "--", Color = [0.45 0.45 0.45], LineWidth = 1.1, ...
     DisplayName = "setpoint");
plot(ax1, tr.t, tr.Vdc, "-", Color = blueprint, LineWidth = 1.5, ...
     DisplayName = "V_{dc}");
xline(ax1, d.meta.evalStart, ":", Color = copper, LineWidth = 1.3, ...
      DisplayName = "evaluation window starts");
hold(ax1, "off");
grid(ax1, "on");
ax1.GridAlpha = 0.12;
ylabel(ax1, "DC bus voltage (V)");
legend(ax1, Location = "best", Box = "off", FontSize = 8);
title(ax1, d.scenario, Interpreter = "none", FontWeight = "normal");

% --- Inverter current ----------------------------------------------------
ax2 = nexttile(tl);
hold(ax2, "on");
yline(ax2,  P.spec.ImaxAbs, "-", Color = danger, LineWidth = 1.1, ...
      DisplayName = sprintf("±%.1f A limit", P.spec.ImaxAbs));
yline(ax2, -P.spec.ImaxAbs, "-", Color = danger, LineWidth = 1.1, ...
      HandleVisibility = "off");
plot(ax2, tr.t, tr.iout, "-", Color = teal, LineWidth = 1.4, ...
     DisplayName = "i_{out}");
hold(ax2, "off");
grid(ax2, "on");
ax2.GridAlpha = 0.12;
ylabel(ax2, "Inverter current (A)");
xlabel(ax2, "Time (s)");
legend(ax2, Location = "best", Box = "off", FontSize = 8);

linkaxes([ax1 ax2], "x");
xlim(ax1, [tr.t(1) tr.t(end)]);

tmp = string(tempname) + ".png";
exportgraphics(fig, tmp, Resolution = 130);
cleanupTmp = onCleanup(@() delete(tmp));

fid = fopen(tmp, "r");
bytes = fread(fid, Inf, "*uint8");
fclose(fid);

uri = "data:image/png;base64," + string(matlab.net.base64encode(bytes));
end

% =============================================================================
function s = metricTd(m, checkName, fmt)
%METRICTD One summary-table cell, dashed when the scenario does not check it.
if m.checks.(checkName).applicable
    s = "<td class=""num"">" + sprintf(fmt, m.checks.(checkName).value) + "</td>";
else
    s = "<td class=""num na"">&mdash;</td>";
end
end

% =============================================================================
function s = verdictChip(m)
%VERDICTCHIP Pass, fail, or passed-but-only-partly-checked.
failed = strings(0);
names  = string(fieldnames(m.checks))';
for n = names
    c = m.checks.(n);
    if c.applicable && ~c.pass
        failed(end+1) = n; %#ok<AGROW>
    end
end

if ~isempty(failed)
    s = "<span class=""chip fail"">FAIL &middot; " + esc(strjoin(failed, ", ")) + "</span>";
elseif numel(string(m.applies)) < numel(names)
    % Partial, not full pass. Saying PASS on a scenario where three of four
    % requirements were never evaluated overstates what was actually shown.
    s = "<span class=""chip partial"">PASS &middot; " + ...
        esc(strjoin(string(m.applies), ", ")) + " only</span>";
else
    s = "<span class=""chip pass"">PASS</span>";
end
end

% =============================================================================
function out = esc(in)
%ESC Minimal HTML escaping for text that lands inside the document.
out = string(in);
out = replace(out, "&", "&amp;");
out = replace(out, "<", "&lt;");
out = replace(out, ">", "&gt;");
out = replace(out, """", "&quot;");
end
