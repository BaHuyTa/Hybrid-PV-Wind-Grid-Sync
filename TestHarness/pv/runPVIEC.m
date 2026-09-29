function R = runPVIEC(opts)
%RUNPVIEC MPPT efficiency of the PV stage by the IEC 62891 / EN 50530 procedure.
%
%   R = runPVIEC                          static matrix + "quick" dynamic set
%   R = runPVIEC(Profile = "allSlopes")   every slope of A and B, one cycle
%   R = runPVIEC(Profile = "full")        A, B, C with the standard's repetitions
%   R = runPVIEC(Dynamic = false)         static only (~10 min)
%
%   Open a pool first to run in parallel -- parpool(2) or parpool(3); each
%   Simscape worker needs ~1.5 GB. Without a pool everything runs serially.
%
%   Reports, in the layout of an EN 50530 test report:
%     static   eta_MPP at 7 power levels x 3 MPP voltages, EUR and CEC weighted
%     dynamic  eta_MPP,dyn per ramp slope, and their mean
%   and saves the lot to pv/results/iec/.
%
%   runPVAll is the harness's own regression suite and stays as it is. This is
%   the one whose numbers can be put next to a datasheet.

arguments
    opts.Profile (1,1) string {mustBeMember(opts.Profile, ["quick" "allSlopes" "full"])} = "quick"
    opts.Variant (1,1) string  = "nominal"
    opts.Static  (1,1) logical = true
    opts.Dynamic (1,1) logical = true
    opts.Save    (1,1) logical = true
end

P = pvParams(opts.Variant);
buildPVModels(opts.Variant);
tStart = tic;

%% Test points
names = string.empty;
if opts.Static
    for T = P.iec.static.tempC
        for L = P.iec.static.levelsPct
            names(end+1) = sprintf("iec_static_L%03d_T%02d", L, T); %#ok<AGROW>
        end
    end
end
if opts.Dynamic
    names = [names, dynamicNames(P, opts.Profile)];
end

%% References first: every run's settle time and denominator depend on them
need = zeros(0, 2);                                  % [G T]
if opts.Static
    [Lg, Tg] = meshgrid(P.iec.static.levelsPct, P.iec.static.tempC);
    need = [need; 10*Lg(:), Tg(:)];
end
if opts.Dynamic
    for s = P.iec.dynamic.seq
        if startsWith(s.name, "C") && opts.Profile ~= "full"; continue; end
        pct  = P.iec.dynamic.refGridPct;
        pct  = pct(pct >= s.lowPct & pct <= s.highPct);
        need = [need; 10*pct(:), 25*ones(numel(pct), 1)]; %#ok<AGROW>
    end
end
need = unique(need, "rows");
fprintf("\nIEC 62891 / EN 50530 MPPT efficiency -- PV stage [%s, profile %s]\n", ...
        opts.Variant, opts.Profile);
fprintf("%d reference points, %d test runs, pool: %s\n", size(need, 1), numel(names), poolText());
for k = 1:size(need, 1)
    pvReference(need(k,1), P, T = need(k,2), Quiet = false);
end

%% Runs -- longest first, so the parallel tail is short
si = Simulink.SimulationInput.empty;
metas = cell(1, numel(names));
for k = 1:numel(names)
    [si(k), ~, metas{k}] = pvSimInput(names(k), Variant = opts.Variant); %#ok<AGROW>
end
[~, ord] = sort(cellfun(@(m) m.stopTime, metas), "descend");
fprintf("Simulating %.0f s of model time...\n", sum(cellfun(@(m) m.stopTime, metas)));
outs(ord) = pvRunMany(si(ord));

res = cellfun(@(o, m) pvIECEfficiency(o, P, m), num2cell(outs), metas, ...
              UniformOutput = false);
res = [res{:}];

%% Report
R.variant = opts.Variant;
R.profile = opts.Profile;
R.when    = datetime("now");
R.runs    = res;
if opts.Static;  R.static  = reportStatic(res([res.kind] == "static"), P);   end
if opts.Dynamic; R.dynamic = reportDynamic(res([res.kind] == "dynamic"), P); end
R.wallTime = toc(tStart);
fprintf("Wall time %.1f min.\n\n", R.wallTime/60);

if opts.Save
    outDir = fullfile(fileparts(mfilename("fullpath")), "results", "iec");
    if ~isfolder(outDir); mkdir(outDir); end
    stem = sprintf("iec_%s_%s_%s", opts.Profile, opts.Variant, ...
                   string(R.when, "yyyyMMdd_HHmm"));
    save(fullfile(outDir, stem + ".mat"), "R");
    plotIEC(R, fullfile(outDir, stem + ".png"));
    fprintf("Saved %s.{mat,png} in pv/results/iec\n\n", stem);
end
end

% -----------------------------------------------------------------------------
function names = dynamicNames(P, profile)
names = string.empty;
for s = P.iec.dynamic.seq
    id = extractBefore(s.name, ":");
    switch profile
        case "quick"
            if id == "C"; continue; end
            slopes = P.iec.dynamic.quickSlopes.(id);
            reps   = ones(size(slopes));
        case "allSlopes"
            if id == "C"; continue; end
            slopes = s.slope;  reps = ones(size(slopes));
        case "full"
            slopes = s.slope;  reps = s.reps;
    end
    for k = 1:numel(slopes)
        names(end+1) = sprintf("iec_dyn_%s_s%g_n%d", id, slopes(k), reps(k)); %#ok<AGROW>
    end
end
end

% -----------------------------------------------------------------------------
function S = reportStatic(res, P)
lv = P.iec.static.levelsPct;
tc = P.iec.static.tempC;
eta = nan(numel(tc), numel(lv));
for r = res
    eta(tc == r.T, lv == r.levelPct) = r.etaPct;
end
w  = @(W, row) sum(W.w .* row(arrayfun(@(l) find(lv == l), W.levels)));
eur = arrayfun(@(i) w(P.iec.static.eurWeights, eta(i,:)), 1:numel(tc))';
cec = arrayfun(@(i) w(P.iec.static.cecWeights, eta(i,:)), 1:numel(tc))';

fprintf("\nSTATIC MPPT EFFICIENCY  eta_MPP [%%]   (pass: EUR-weighted >= %g %% at every voltage)\n", ...
        P.spec.iecStaticEurPct);
fprintf("%s\n", repmat('=', 1, 96));
fprintf("%-17s", "level [% of STC]"); fprintf("%8d", lv); fprintf("%9s%9s\n", "EUR", "CEC");
fprintf("%s\n", repmat('-', 1, 96));
for i = 1:numel(tc)
    fprintf("%-17s", P.iec.static.tempLabel(i)); fprintf("%8.2f", eta(i,:));
    fprintf("%9.2f%9.2f\n", eur(i), cec(i));
end
fprintf("%s\n", repmat('-', 1, 96));
S = struct(levelsPct = lv, tempC = tc, etaPct = eta, eurPct = eur, cecPct = cec, ...
           pass = all(eur >= P.spec.iecStaticEurPct));
fprintf("Static: %s (lowest EUR %.2f %%)\n", passText(S.pass), min(eur));
end

% -----------------------------------------------------------------------------
function D = reportDynamic(res, P)
fprintf("\nDYNAMIC MPPT EFFICIENCY  eta_MPP,dyn [%%]   (pass: mean >= %g %%)\n", ...
        P.spec.iecDynamicPct);
fprintf("%s\n", repmat('=', 1, 96));
fprintf("%-22s %12s %8s %12s %12s\n", "sequence", "slope[W/m2/s]", "cycles", "duration[s]", "eta[%]");
fprintf("%s\n", repmat('-', 1, 96));
[~, o] = sortrows([double([res.seq])' , [res.slope]']);
res = res(o);
for r = res
    fprintf("%-22s %12g %8d %12.0f %12.2f\n", ...
            P.iec.dynamic.seq(double(r.seq) - double('A') + 1).name, ...
            r.slope, r.cycles, r.duration, r.etaPct);
end
fprintf("%s\n", repmat('-', 1, 96));
D = struct(seq = [res.seq], slope = [res.slope], etaPct = [res.etaPct], ...
           meanPct = mean([res.etaPct]), minPct = min([res.etaPct]));
D.pass = D.meanPct >= P.spec.iecDynamicPct;
fprintf("Dynamic: %s (mean %.2f %%, worst %.2f %%)\n", passText(D.pass), D.meanPct, D.minPct);
end

% -----------------------------------------------------------------------------
function plotIEC(R, file)
f = figure(Visible = "off", Position = [100 100 1200 800]);
tl = tiledlayout(f, 2, 2, TileSpacing = "compact");
title(tl, sprintf("PV stage MPPT efficiency, IEC 62891 / EN 50530 [%s, %s]", R.variant, R.profile));
if isfield(R, "static")
    ax = nexttile(tl);
    plot(ax, R.static.levelsPct, R.static.etaPct', "-o", LineWidth = 1.5);
    legend(ax, compose("%d C", R.static.tempC), Location = "southeast");
    xlabel(ax, "Power level [% of STC]"); ylabel(ax, "\eta_{MPP} [%]"); grid(ax, "on");
    title(ax, "Static");
end
if isfield(R, "dynamic")
    ax = nexttile(tl);
    dyn = R.runs([R.runs.kind] == "dynamic");
    for s = unique([dyn.seq])
        d = dyn([dyn.seq] == s);
        semilogx(ax, [d.slope], [d.etaPct], "-o", LineWidth = 1.5, DisplayName = "Seq " + s);
        hold(ax, "on");
    end
    legend(ax, Location = "southwest");
    xlabel(ax, "Ramp slope [W/m^2/s]"); ylabel(ax, "\eta_{MPP,dyn} [%]"); grid(ax, "on");
    title(ax, "Dynamic");

    [~, iw] = min([dyn.etaPct]);
    w = dyn(iw);
    ax = nexttile(tl, [1 2]);
    plot(ax, w.trace.t, w.trace.P/1e3, DisplayName = "P_{panel}"); hold(ax, "on");
    plot(ax, w.trace.tRef, w.trace.Pmpp/1e3, "--", LineWidth = 1.5, DisplayName = "P_{MPP} available");
    yyaxis(ax, "right"); plot(ax, w.trace.t, w.trace.V, DisplayName = "V_{panel}");
    ylabel(ax, "V [V]"); yyaxis(ax, "left");
    ylabel(ax, "Power [kW]"); xlabel(ax, "Time [s]"); grid(ax, "on"); legend(ax, Location = "best");
    title(ax, sprintf("Worst dynamic run: %s (%.2f %%)", w.scenario, w.etaPct), Interpreter = "none");
end
exportgraphics(f, file, Resolution = 150);
close(f);
end

% -----------------------------------------------------------------------------
function s = passText(p)
if p; s = "PASS"; else; s = "FAIL"; end
end

function s = poolText()
p = gcp("nocreate");
if isempty(p); s = "none (serial)"; else; s = sprintf("%d workers", p.NumWorkers); end
end
