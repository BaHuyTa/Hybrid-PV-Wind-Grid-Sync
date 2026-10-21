function scn = intScenarios(names)
%INTSCENARIOS  The integration test scenarios. Each is weather in, output out.
%
%   scn = intScenarios()            all of them
%   scn = intScenarios("cloud")     just the named ones
%   scn = intScenarios("day")       the four real-day profile runs (not in "all": ~25 min each)
%   scn = intScenarios("demo")      the extra event clips for demo/LiveDemo (not in "all")
%   scn = intScenarios("webdemo")   the web demo matrix: 5 loads x {normal, dip, shed, island}
%
% Fields: name, T (stop time), G (@(t) W/m^2), v_wind (@(t) m/s), T_cell (degC),
% v_wind0 (the wind speed the turbine starts settled at), window ([t0 t1],
% where steady-state metrics are read), block (optional {path, param, value}
% overrides, relative to the model root), set (optional {"field.path", value}
% overrides of intParams, e.g. breaker and trip times) and why (one line).

s = struct([]);

s(end+1).name = "nominal";
s(end).why    = "Sources come up onto the bus from t = 0; steady output read at the end.";
s(end).T      = 1.0;
s(end).G      = @(t) 1000 + 0*t;
s(end).v_wind = @(t) 8 + 0*t;
s(end).v_wind0 = 8;
s(end).window = [0.8 1.0];

s(end+1).name = "cloud";
s(end).why    = "Irradiance collapses 1000 -> 200 W/m^2 at 0.4 s and returns at 0.7 s (a step, the worst case).";
s(end).T      = 1.0;
s(end).G      = @(t) 1000 - 800*(t >= 0.4 & t < 0.7);
s(end).v_wind = @(t) 8 + 0*t;
s(end).v_wind0 = 8;
s(end).window = [0.6 0.7];            % steady while shaded

s(end+1).name = "gust";
s(end).why    = "Wind steps 8 -> 12 m/s at 0.3 s. The rotor is slow (H = 3 s), so power climbs over seconds.";
s(end).T      = 2.0;
s(end).G      = @(t) 1000 + 0*t;
s(end).v_wind = @(t) 8 + 4*(t >= 0.3);
s(end).v_wind0 = 8;
s(end).window = [1.8 2.0];

s(end+1).name = "over_rating";
s(end).why    = "Full sun AND rated wind: about 173 kW into a 150 kVA inverter. PV curtailment must hold the bus near 720 V.";
s(end).T      = 0.5;
s(end).G      = @(t) 1000 + 0*t;
s(end).v_wind = @(t) 12 + 0*t;
s(end).v_wind0 = 12;
s(end).window = [0.4 0.5];

s(end+1).name = "weak_grid";
s(end).why    = "Nominal weather on an SCR = 3 grid (X/R 15), the success-criteria floor. Per-unit study, not a site claim.";
s(end).T      = 1.0;
s(end).G      = @(t) 1000 + 0*t;
s(end).v_wind = @(t) 8 + 0*t;
s(end).v_wind0 = 8;
s(end).window = [0.8 1.0];
% Grid impedance ON (ip.SCR = 3, ip.grid_XR = 15 already). Set as a literal block
% parameter: overriding ip.grid_Z_opt through the model workspace fails to
% compile in the integration model ("G_parasitic ... got type string"), even
% though the same override works on Duc's standalone model.
s(end).block  = {"Inverter/GridSide/Grid", "impedance_option", "1"};

% ---- Protection path (trip + PCC breakers). The trip is a stand-in Step until
% Redhwan's 47/52 Hz trip signal is wired in. Field "set" overrides intParams.
s(end+1).name = "trip";
s(end).why    = "Nominal weather; the trip fires at 0.5 s. Inverter current, PV boost and wind boost must all stop, and the bus must stay put.";
s(end).T      = 0.8;
s(end).G      = @(t) 1000 + 0*t;
s(end).v_wind = @(t) 8 + 0*t;
s(end).v_wind0 = 8;
s(end).window = [0.3 0.5];            % steady, before the trip
s(end).set    = {"trip.t", 0.5};

s(end+1).name = "island";
s(end).why    = "Matched RLC load in, site load out; the grid breaker opens at 0.5 s and the trip fires 0.1 s later (Redhwan's SFS: 98 ms).";
s(end).T      = 0.8;
s(end).G      = @(t) 1000 + 0*t;
s(end).v_wind = @(t) 8 + 0*t;
s(end).v_wind0 = 8;
s(end).window = [0.3 0.5];            % steady, grid-connected
s(end).set    = {"pcc.rlc.open0", 0, "pcc.site.open0", 1, "pcc.grid.t", 0.5, "trip.t", 0.6};

% ---- Anti-islanding on its own (5 Oct): SFS + Redhwan's relay, NO stand-in trip.
% Needs a model with SFS and the relay (intSystem_aqibPLL); on the reference
% intSystem nothing trips, which is the passive-blind result of "island".
s(end+1).name = "island_sfs";
s(end).why    = "Matched RLC load in, site load out; the grid breaker opens at 0.5 s and nothing else: SFS must push f out of 47-52 Hz and the relay must trip by itself (limit 2 s).";
s(end).T      = 1.0;
s(end).G      = @(t) 1000 + 0*t;
s(end).v_wind = @(t) 8 + 0*t;
s(end).v_wind0 = 8;
s(end).window = [0.3 0.5];            % steady, grid-connected
s(end).set    = {"pcc.rlc.open0", 0, "pcc.site.open0", 1, "pcc.grid.t", 0.5};

% ---- Grid fault ride-through (14 Oct sandbox, shipped 19 Oct). A fault the GRID
% clears: our breakers stay closed, nothing may trip, power must come back.
% AEMO short-duration undervoltage test (used for AS/NZS 4777.2): 50 V for 220 ms.
% R = 0.024 ohm leaves ~35 V rms (0.15 pu), slightly harsher than 50 V. The grid
% needs an impedance for the fault to drop voltage across: SCR 10, X/R 15.
% Needs a model with Inverter/GridSide/GridFault (intSystem_aqibPLL).
s(end+1).name = "grid_dip";
s(end).why    = "Nominal weather; a three-phase fault at the PCC from 0.5 s for 220 ms (0.15 pu left), cleared by the grid. Ride through: no trip, bus < 800 V, power back within 1 s.";
s(end).T      = 1.5;
s(end).G      = @(t) 1000 + 0*t;
s(end).v_wind = @(t) 8 + 0*t;
s(end).v_wind0 = 8;
s(end).window = [0.3 0.5];            % steady, before the fault
s(end).set    = {"flt.R", 0.024, "flt.t", 0.5, "flt.dur", 0.22};
s(end).block  = {"Inverter/GridSide/Grid", "impedance_option", "1", ...
                 "Inverter/GridSide/Grid", "SShortCircuit", "1.5e6"};   % SCR 10 x 150 kVA

% ---- A real day (19 Oct). Product owner, W10: a measured wind/solar profile instead
% of steps, the site load at min / mid / max, load shedding mid-run, and a comparison.
% Weather: Gullen Range (NSW) solar + wind farms, 6 Oct 2026 06:00-14:00, AEMO 5-min
% SCADA, scaled to our plant and compressed 5 min -> 50 ms (see gullenProfile). The
% turbine inertia is scaled with it (Jscale): at H = 3 s the rotor would lag the
% compressed wind by hours of real time; at H = 0.05 s it settles inside one sample,
% which is all 5-minute data can resolve. Grid SCR 10 (X/R 15), so the load level
% moves the PCC voltage. profile = true: only start-up counts as a bus disturbance.
dp = gullenProfile();
loads = [50 150 250 100 200];  tags = ["min","mid","max","100","200"];   % 100/200: web demo (21 Oct)
for j = 1:numel(loads)
    s(end+1).name = "day_load_" + tags(j); %#ok<AGROW>
    s(end).why    = sprintf("Real day (Gullen NSW, 6 Oct 2026, 06:00-14:00 in %.1f s); site load %d kW.", dp.T, loads(j));
    s(end).set    = {"pcc.site.P", loads(j)*1e3};
end
s(end+1).name = "day_shed";
s(end).why    = sprintf("Real day as above, site load 250 kW shed (breaker opens) at 10:00 = %.1f s.", dp.at("10:00"));
s(end).set    = {"pcc.site.t", dp.at("10:00")};
for k = numel(s)-numel(loads):numel(s)
    s(k).T = dp.T;  s(k).G = dp.Gf;  s(k).v_wind = dp.vf;  s(k).v_wind0 = dp.v(1);
    s(k).window  = [2.6 2.7];          % 10:20-10:30 real: full sun, after the shed, 5 cycles
    s(k).profile = true;  s(k).Jscale = 1/60;
    s(k).block   = {"Inverter/GridSide/Grid", "impedance_option", "1", ...
                    "Inverter/GridSide/Grid", "SShortCircuit", "1.5e6"};
end

% ---- Live demo app (20 Oct, roadshow). Every event at the same operating point
% as grid_dip (nominal weather, SCR 10), so the site load is the only thing that
% changes between clips. grid_dip itself is the 250 kW case. Not in "all".
k0 = find([s.name] == "grid_dip");
for P = [50 150]
    s(end+1) = s(k0); %#ok<AGROW>
    s(end).name = "grid_dip_" + P;
    s(end).why  = sprintf("grid_dip with a %d kW site load (grid_dip is 250 kW).", P);
    s(end).set  = [s(k0).set, {"pcc.site.P", P*1e3}];
    s(end).demo = true;
end
for P = [50 150 250]
    s(end+1).name = "shed_" + P; %#ok<AGROW>
    s(end).why    = sprintf("Nominal weather, SCR 10, %d kW site load; its breaker opens at 0.5 s. The PCC phase steps, the PLL swings, nothing may trip.", P);
    s(end).T      = 1.0;
    s(end).G      = @(t) 1000 + 0*t;
    s(end).v_wind = @(t) 8 + 0*t;
    s(end).v_wind0 = 8;
    s(end).window = [0.3 0.5];        % steady, before the shed
    s(end).set    = {"pcc.site.P", P*1e3, "pcc.site.t", 0.5};
    s(end).block  = s(k0).block;      % SCR 10, X/R 15
    s(end).demo   = true;
end
k1 = find([s.name] == "island_sfs");
s(end+1) = s(k1);
s(end).name = "island_nosfs";
s(end).why  = "island_sfs with SFS switched off: on the matched load the frequency stays in band, so the relay alone never trips (limit 2 s).";
s(end).T    = 2.6;
s(end).set  = [s(k1).set, {"sfs.cf0", 0, "sfs.kSFS", 0}];
s(end).demo = true;

% ---- Web demo matrix (21 Oct; Final_Showcase/LiveDemo, outside git). The visitor picks the
% factory load (50-250 kW) and one event. Same operating point as grid_dip (nominal weather,
% SCR 10), event at 0.5 s. Unlike demo/LiveDemo's grid-lost case (matched test load), here the
% grid is lost with the FACTORY still connected: the bus charges to ~770-837 V before the trip.
%   normal  nothing happens               dip     grid_dip's fault (0.15 pu, 220 ms)
%   shed    the factory's breaker opens   island  the grid's breaker opens (factory stays on)
ev = struct('tag', {"normal","dip","shed","island"}, 'T', {1.5, 1.5, 1.5, 1.0}, ...
    'set', {{}, {"flt.R", 0.024, "flt.t", 0.5, "flt.dur", 0.22}, {"pcc.site.t", 0.5}, {"pcc.grid.t", 0.5}}, ...
    'why', {"no event", "grid fault at 0.5 s for 220 ms, 0.15 pu left", "factory load shed at 0.5 s", ...
            "grid lost at 0.5 s with the factory still connected"});
for L = 50:50:250
    for e = ev
        s(end+1).name = sprintf("demo_L%03d_%s", L, e.tag); %#ok<AGROW>
        s(end).why    = sprintf("Web demo: %d kW factory, nominal weather; %s.", L, e.why);
        s(end).T      = e.T;
        s(end).G      = @(t) 1000 + 0*t;
        s(end).v_wind = @(t) 8 + 0*t;
        s(end).v_wind0 = 8;
        s(end).window = [0.3 0.5];
        s(end).set    = [{"pcc.site.P", L*1e3}, e.set];
        s(end).block  = {"Inverter/GridSide/Grid", "impedance_option", "1", ...
                         "Inverter/GridSide/Grid", "SShortCircuit", "1.5e6"};
        s(end).webdemo = true;
    end
end

[s.T_cell] = deal(25);
for k = 1:numel(s)
    if isempty(s(k).block), s(k).block = {}; end
    if isempty(s(k).set),   s(k).set   = {}; end
    if isempty(s(k).profile), s(k).profile = false; end
    if isempty(s(k).Jscale),  s(k).Jscale  = 1; end
    if isempty(s(k).demo),    s(k).demo    = false; end
    if isempty(s(k).webdemo), s(k).webdemo = false; end
end

if nargin && ~isempty(names)
    names = string(names);
    if any(names == "day"),  names = [names, [s([s.profile]).name]]; end
    if any(names == "demo"), names = [names, [s([s.demo]).name]]; end
    if any(names == "webdemo"), names = [names, [s([s.webdemo]).name]]; end
    s = s(ismember([s.name], names));
else
    s = s(~[s.profile] & ~[s.demo] & ~[s.webdemo]);   % real-day runs and demo clips only when asked for
end
scn = s;
end
