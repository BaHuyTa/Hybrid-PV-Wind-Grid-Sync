function [out, P, meta, ref] = runPVScenario(scenario, opts)
%RUNPVSCENARIO Run one named scenario against the PV boost + MPPT stage.
%
%   [out, P, meta, ref] = runPVScenario("full_sun")
%   [out, P, meta, ref] = runPVScenario("cloud_step_down", Variant = "fastPO")
%
%   This is the ONLY place the PV model is simulated. Interactive exploration
%   and the automated tests both come through here, for the same reason the
%   DC-link harness works that way: if the tests build their own
%   SimulationInput and you build a different one by hand at the command line,
%   you eventually hit the worst class of bug -- "it passes the test but fails
%   when I run it", or the reverse. One entry point makes that impossible.

arguments
    scenario     (1,1) string
    opts.Variant (1,1) string  = "nominal"
end

P = pvParams(opts.Variant);
buildPVModels(opts.Variant);

[irrProfile, P, meta] = pvScenarios(scenario, P);

here = fileparts(mfilename("fullpath"));
mdl  = P.uut.model;
if ~bdIsLoaded(mdl)
    load_system(fullfile(fileparts(here), "models", mdl + ".slx"));
end

% The reference is fetched before the run, not after, so a cache miss costs its
% sweep once and every later scenario at the same irradiance is free.
ref = pvReference(meta.irrFinal, P, Quiet = true);

si = Simulink.SimulationInput(mdl);
si = si.setVariable("irrProfile", irrProfile);
si = si.setModelParameter(StopTime = num2str(meta.stopTime));

out = sim(si);
end
