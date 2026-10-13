function scn = intScenarios(names)
%INTSCENARIOS  The integration test scenarios. Each is weather in, output out.
%
%   scn = intScenarios()            all of them
%   scn = intScenarios("cloud")     just the named ones
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
s(end).why    = "Full sun AND rated wind: about 173 kW into a 150 kVA inverter. Nothing curtails the sources.";
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

[s.T_cell] = deal(25);
for k = 1:numel(s)
    if isempty(s(k).block), s(k).block = {}; end
    if isempty(s(k).set),   s(k).set   = {}; end
end

if nargin && ~isempty(names)
    s = s(ismember([s.name], string(names)));
end
scn = s;
end
