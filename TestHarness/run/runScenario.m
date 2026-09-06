function [out, P, meta, ds] = runScenario(scenario, opts)
%RUNSCENARIO Run one named scenario against the DC-link loop model.
%
%   [out, P, meta, ds] = runScenario("source_step")
%   [out, P, meta, ds] = runScenario("source_step", Variant = "sluggish")
%   [out, P, meta, ds] = runScenario("source_step", LogToSDI = true)
%
%   This is the ONLY place the model is simulated. Interactive exploration and
%   the automated tests both come through here.
%
%   That matters more than it looks. If the tests built their own
%   SimulationInput and you built a different one by hand at the command line,
%   you would eventually hit the worst class of bug: "it passes the test but
%   fails when I run it", or the reverse. One entry point makes that impossible
%   -- there is only one way the model can be run.
%
%   Name-value arguments:
%     Variant   "nominal" (default) or "sluggish"
%     LogToSDI  false (default). When true the run is pushed to the Simulation
%               Data Inspector under a descriptive name.

arguments
    scenario        (1,1) string
    opts.Variant    (1,1) string  = "nominal"
    opts.LogToSDI   (1,1) logical = false
end

mdl = "DCLinkLoop";

% Build the model if it has never been built, or if the build script is newer
% than the .slx. This is what stops the classic failure where someone edits the
% build script, forgets to re-run it, and tests the stale model.
ensureModelIsCurrent(mdl);

P = harnessParams(opts.Variant);
[ds, P, meta] = createTestInputs(scenario, P);

simIn = Simulink.SimulationInput(mdl);
simIn = simIn.setVariable("P", P);          % params travel with the run, not
                                            % via the base workspace
simIn = simIn.setExternalInput(ds);
simIn = simIn.setModelParameter(StopTime = num2str(meta.stopTime));

out = sim(simIn);

meta.variant = opts.Variant;
meta.runName = sprintf("%s [%s]", scenario, opts.Variant);

if opts.LogToSDI
    meta.sdiRunID = pushToSDI(out, meta);
end
end

% -----------------------------------------------------------------------------
function ensureModelIsCurrent(mdl)
%ENSUREMODELISCURRENT Rebuild the .slx if the build script has moved ahead of it.
here     = fileparts(fileparts(mfilename("fullpath")));
slxFile  = fullfile(here, "models", mdl + ".slx");
bldFile  = fullfile(here, "models", "build" + mdl + ".m");

needsBuild = ~isfile(slxFile);
if ~needsBuild
    slxInfo = dir(slxFile);
    bldInfo = dir(bldFile);
    needsBuild = bldInfo.datenum > slxInfo.datenum;
end

if needsBuild
    if bdIsLoaded(mdl)
        close_system(mdl, 0);
    end
    feval("build" + mdl);
end
end

% -----------------------------------------------------------------------------
function runID = pushToSDI(out, meta)
%PUSHTOSDI Record this run in the Simulation Data Inspector.
%
%   SDI is the harness's memory. Without it every run overwrites the last one in
%   your head, and "it looked fine yesterday" is unfalsifiable. With it you can
%   pull up last week's run and diff it against today's.
runID = Simulink.sdi.createRun(meta.runName, "namevalue", ...
    {"Vdc", "i_out", "e"}, ...
    {out.logsout.get("Vdc").Values, ...
     out.logsout.get("i_out").Values, ...
     out.logsout.get("e").Values});
end
