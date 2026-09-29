function [si, P, meta, ref] = pvSimInput(scenario, opts)
%PVSIMINPUT The one SimulationInput for a named PV scenario.
%
%   [si, P, meta, ref] = pvSimInput("full_sun")
%   [si, P, meta, ref] = pvSimInput("iec_dyn_B_s100_n1", Variant = "fastPO")
%
%   Everything that decides what a run means -- which model, which irradiance,
%   which cell temperature, what holds the bus -- is set here and nowhere else.
%   runPVScenario runs one of these; runPVIEC runs an array of them in parallel.

arguments
    scenario     (1,1) string
    opts.Variant (1,1) string  = "nominal"
end

P = pvParams(opts.Variant);
buildPVModels(opts.Variant);

[irrProfile, P, meta] = pvScenarios(scenario, P);
if ~isfield(meta, "T"); meta.T = 25; end
if ~isfield(meta, "kind"); meta.kind = "regression"; end

% Standards runs go to the energy-logging copy; see buildPVModels.
if startsWith(scenario, "iec_")
    mdl = P.uut.iecModel;
else
    mdl = P.uut.model;
end
here = fileparts(mfilename("fullpath"));
if ~bdIsLoaded(mdl)
    load_system(fullfile(fileparts(here), "models", mdl + ".slx"));
end

% The reference is fetched before the run, not after, so a cache miss costs its
% sweep once and every later scenario at the same operating point is free.
ref = pvReference(meta.irrFinal, P, T = meta.T, Quiet = true);

si = Simulink.SimulationInput(mdl);
si = si.setVariable("irrProfile", irrProfile);
si = si.setModelParameter(StopTime = num2str(meta.stopTime));
si = si.setBlockParameter(mdl + "/Solar Panel", "CellTempC", num2str(meta.T));
si = pvBusInput(si, P, meta.stopTime);
meta.irrProfile = irrProfile;
end
