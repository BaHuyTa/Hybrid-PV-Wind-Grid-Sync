function [irrProfile, P, meta] = pvIECScenario(scenario, P)
%PVIECSCENARIO Irradiance profiles for the IEC 62891 / EN 50530 MPPT test.
%
%   [irrProfile, P, meta] = pvIECScenario("iec_static_L050_T25", P)
%   [irrProfile, P, meta] = pvIECScenario("iec_dyn_B_s100_n1",   P)
%
%   Names encode the test point, so every run is reproducible from its name:
%     iec_static_L<level %>_T<cell temp C>
%     iec_dyn_<A|B|C>_s<slope W/m^2/s>_n<cycles>
%
%   Called through pvScenarios, so the IEC runs share runPVScenario and its
%   SimulationInput with every other PV run. Numbers come from P.iec; see
%   pvParams for where each one came from.

arguments
    scenario (1,1) string
    P struct = pvParams()
end

meta.scenario = scenario;
meta.event    = NaN;
meta.applies  = string.empty;   % judged by pvIECEfficiency, not evaluatePVSpec
meta.variant  = P.ctrl.variant;
meta.runName  = sprintf("%s [%s]", scenario, P.ctrl.variant);

tok = regexp(scenario, "^iec_static_L(\d+)_T(\d+)$", "tokens", "once");
if ~isempty(tok)
    level = str2double(tok{1});
    meta.kind     = "static";
    meta.levelPct = level;
    meta.T        = str2double(tok{2});
    G             = 10 * level;             % 100 % = 1000 W/m^2 (Annex B.1)
    meta.irrFinal = G;

    % Wait for the tracker to arrive, then measure. The standard's wording is
    % "the stabilisation of the MPP tracking must be awaited firstly"; here the
    % wait is the walk from P&O's start voltage to this point's peak, at the
    % slew rate the algorithm is capable of, with half as much again in hand.
    meta.evalStart = settleTime(G, meta.T, P);
    meta.stopTime  = meta.evalStart + P.iec.static.window;
    meta.evalEnd   = meta.stopTime;
    meta.description = sprintf("Static MPPT, %d %% (%d W/m^2), cell %d C", ...
                               level, G, meta.T);
    irrProfile = timeseries([G; G], [0; meta.stopTime]);
    return
end

tok = regexp(scenario, "^iec_dyn_([ABC])_s([\d.]+)_n(\d+)$", "tokens", "once");
if isempty(tok)
    error("pvIECScenario:badName", ...
          "Not an IEC scenario name: ""%s"". See the help text.", scenario);
end
id     = char(tok{1});
seq    = P.iec.dynamic.seq(id - 'A' + 1);
slope  = str2double(tok{2});
cycles = str2double(tok{3});
if ~any(abs(seq.slope - slope) < 1e-9)
    error("pvIECScenario:badSlope", ...
          "%g W/m^2/s is not a slope of sequence %s in the standard.", slope, seq.name);
end

lo    = 10 * seq.lowPct;
hi    = 10 * seq.highPct;
tRamp = (hi - lo) / slope;

meta.kind     = "dynamic";
meta.seq      = id;
meta.seqName  = seq.name;
meta.slope    = slope;
meta.cycles   = cycles;
meta.T        = 25;                          % the standard runs these at STC
meta.irrFinal = lo;
meta.levelsWm2 = [lo hi];

% Standard: 300 s initial wait. Here: until the tracker has arrived at the low
% level's peak. Excluded from the energy integral in both cases.
wait = settleTime(lo, meta.T, P);

% One cycle: ramp up, dwell at the top, ramp down, dwell at the bottom.
tk = wait; t = [0; wait]; g = [lo; lo];
for c = 1:cycles
    tk = tk + tRamp;      t(end+1) = tk; g(end+1) = hi; %#ok<AGROW>
    tk = tk + seq.dwell;  t(end+1) = tk; g(end+1) = hi; %#ok<AGROW>
    tk = tk + tRamp;      t(end+1) = tk; g(end+1) = lo; %#ok<AGROW>
    tk = tk + seq.dwell;  t(end+1) = tk; g(end+1) = lo; %#ok<AGROW>
end
irrProfile = timeseries(g, t);

meta.evalStart = wait;
meta.stopTime  = tk;
meta.evalEnd   = tk;
meta.description = sprintf("Dynamic MPPT, sequence %s at %g W/m^2/s, %d cycle(s)", ...
                           seq.name, slope, cycles);
end

% -----------------------------------------------------------------------------
function t = settleTime(G, T, P)
%SETTLETIME How long P&O needs to walk from its start voltage to the peak.
ref  = pvReference(G, P, T = T, Quiet = true);
walk = abs(P.ctrl.Vstart - ref.Vpv) / P.ctrl.slewRate;
t    = 1.5 * walk + P.iec.static.settleMargin;
end
