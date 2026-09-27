function [out, P, meta, ref] = runPVScenario(scenario, opts)
%RUNPVSCENARIO Run one named scenario against the PV boost + MPPT stage.
%
%   [out, P, meta, ref] = runPVScenario("full_sun")
%   [out, P, meta, ref] = runPVScenario("cloud_step_down", Variant = "fastPO")
%   [out, P, meta, ref] = runPVScenario("iec_static_L050_T75")
%
%   This is the ONLY place the PV model is simulated. Interactive exploration
%   and the automated tests both come through here, for the same reason the
%   DC-link harness works that way: if the tests build their own
%   SimulationInput and you build a different one by hand at the command line,
%   you eventually hit the worst class of bug -- "it passes the test but fails
%   when I run it", or the reverse. One entry point makes that impossible.
%
%   Batch runs (runPVIEC) build the same inputs through pvSimInput and hand the
%   whole array to pvRunMany; this function is that path for a single run.

arguments
    scenario     (1,1) string
    opts.Variant (1,1) string  = "nominal"
end

[si, P, meta, ref] = pvSimInput(scenario, Variant = opts.Variant);
out = pvRunMany(si);
end
