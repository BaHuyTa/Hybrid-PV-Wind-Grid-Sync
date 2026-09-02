function buildPVModels(variant, opts)
%BUILDPVMODELS Instrument Belal's PV model so it can be tested, without editing it.
%
%   buildPVModels()                       rebuild "nominal" if out of date
%   buildPVModels("fastPO")               build the candidate-fix variant
%   buildPVModels("nominal", Force = true)
%
%   Belal's solarsimulink.slx cannot be tested as delivered. Not because it is
%   wrong -- because it was built to be watched, not measured:
%
%     1. Irradiance is a Constant block. There is no way to make it do anything.
%     2. The four interesting signals go to a Scope and nowhere else. A Scope is
%        a window, not a record; nothing downstream can read what it displays.
%     3. No signal is marked for logging, so a run produces no data at all.
%
%   So this generates instrumented COPIES and leaves the original alone:
%
%     pvUUT.slx    irradiance driven from the workspace, V/I/Vdc/Duty logged,
%                  MPPT untouched. This is the model under test.
%     pvSweep.slx  identical plant, but the P&O block is replaced by a constant
%                  duty. This is the independent reference -- the ceiling the
%                  MPPT gets scored against. It is a separate model rather than
%                  a switch inside pvUUT because a test rig that can be put into
%                  "not actually testing anything" mode eventually is.
%     pvUUT_<v>.slx  a variant with the P&O perturbation size patched.
%
%   Regenerated, never hand-edited. The moment someone fixes a bug in a copy
%   instead of in the source, the harness starts certifying a model that is not
%   the one being shipped.

arguments
    variant    (1,1) string  = "nominal"
    opts.Force (1,1) logical = false
end

here   = fileparts(mfilename("fullpath"));
outDir = fullfile(fileparts(here), "models");
P      = pvParams(variant);
src    = fullfile(fileparts(fileparts(here)), "Belal's PV", "solarsimulink.slx");

if ~isfile(src)
    error("buildPVModels:noSource", ...
          "Cannot find the source model at\n  %s\nUpdate the path in " + ...
          "pv/buildPVModels.m if it has moved.", src);
end

uut   = fullfile(outDir, P.uut.model      + ".slx");
sweep = fullfile(outDir, P.uut.sweepModel + ".slx");

if ~opts.Force && isfile(uut) && isfile(sweep)
    s = dir(src);
    b = dir(fullfile(here, "buildPVModels.m"));
    u = dir(uut);
    if u.datenum > s.datenum && u.datenum > b.datenum
        return   % copies are current
    end
end

for m = [P.uut.model, P.uut.sweepModel]
    if bdIsLoaded(m); close_system(m, 0); end
end

%% pvUUT -- driveable input, logged outputs
copyfile(src, uut, "f");
load_system(uut);
mdl = char(P.uut.model);

% Irradiance: Constant -> From Workspace.
% One mechanism covers every scenario. A steady 1000 W/m^2 is just a two-point
% profile, so there is no separate code path for "constant" cases to drift out
% of agreement with the stepped ones.
pos = get_param([mdl '/Constant'], "Position");
delete_line(mdl, "Constant/1", "Solar Panel/1");
delete_block([mdl '/Constant']);
add_block("simulink/Sources/From Workspace", [mdl '/Irradiance Profile'], ...
          Position              = pos + [-40 -5 10 5], ...
          VariableName          = "irrProfile", ...
          SampleTime            = "0", ...
          Interpolate           = "on", ...
          OutputAfterFinalValue = "Holding final value");
add_line(mdl, "Irradiance Profile/1", "Solar Panel/1", autorouting = "on");

% Logging.
% Set on the PORT handle, not the line. Line-level DataLogging was removed in
% R2026a, and setting it there fails with "line does not have a parameter named
% 'DataLogging'" -- which reads like the signal is wrong rather than the handle.
sigs = { "PV Sensors",      1, "I"    ; ...
         "PV Sensors",      2, "V"    ; ...
         "Boost Converter", 1, "Vdc"  ; ...
         "MPPT Controller", 1, "Duty" };
for k = 1:size(sigs, 1)
    ph = get_param(mdl + "/" + sigs{k,1}, "PortHandles");
    set_param(ph.Outport(sigs{k,2}), ...
              DataLogging         = "on", ...
              DataLoggingNameMode = "Custom", ...
              DataLoggingName     = sigs{k,3});
end
set_param(mdl, SignalLogging = "on", SignalLoggingName = "logsout", ...
               SaveFormat    = "Dataset");

% Variant: patch the perturbation size in the P&O source.
% Targeted at the exact assignment rather than a blanket replace, and verified,
% because a silent no-op here would produce a "variant" identical to nominal --
% and the run would look like proof that dD does not matter.
if variant ~= "nominal"
    patchPerturbation(mdl, P.ctrl.dD);
end

save_system(mdl, uut);
close_system(mdl, 0);

%% pvSweep -- same plant, MPPT swapped for a fixed duty
% Built only once, from the nominal copy: the reference is a property of the
% plant, and the plant is the same in every variant.
if variant == "nominal" || ~isfile(sweep)
    copyfile(uut, sweep, "f");
    load_system(sweep);
    mdl = char(P.uut.sweepModel);
    sub = [mdl '/MPPT Controller'];

    delete_line(sub, "V/1",       "PO MPPT/1");
    delete_line(sub, "I/1",       "PO MPPT/2");
    delete_line(sub, "PO MPPT/1", "Duty/1");
    delete_line(sub, "PO MPPT/1", "Duty Delay/1");
    pos = get_param([sub '/PO MPPT'], "Position");
    delete_block([sub '/PO MPPT']);

    add_block("simulink/Sources/Constant", [sub '/D_fix'], Position = pos, Value = "D_fix");
    add_line(sub, "D_fix/1", "Duty/1",       autorouting = "on");
    add_line(sub, "D_fix/1", "Duty Delay/1", autorouting = "on");

    % The sensor inports now feed nothing, and Simulink treats an unconnected
    % Inport output as an error. They are terminated rather than deleted so both
    % models still present the same interface to runPVScenario.
    for s = ["V", "I"]
        p = get_param(sub + "/" + s, "Position");
        add_block("simulink/Sinks/Terminator", sub + "/Term_" + s, ...
                  Position = p + [90 0 90 0]);
        add_line(sub, s + "/1", "Term_" + s + "/1", autorouting = "on");
    end

    save_system(mdl, sweep);
    close_system(mdl, 0);
end

fprintf("Built %s (dD = %.3f) from solarsimulink.slx\n", P.uut.model, P.ctrl.dD);
end

% -----------------------------------------------------------------------------
function patchPerturbation(mdl, dD)
%PATCHPERTURBATION Rewrite the dD literal inside the P&O MATLAB Function block.
chart = sfroot().find("-isa", "Stateflow.EMChart", ...
                      "Path", mdl + "/MPPT Controller/PO MPPT");
if isempty(chart)
    error("buildPVModels:noChart", "Could not find the PO MPPT function block.");
end

old = chart.Script;
new = regexprep(old, "dD\s*=\s*[\d.eE+-]+\s*;", sprintf("dD = %g;", dD), "once");
if strcmp(new, old)
    error("buildPVModels:patchFailed", ...
          "The dD assignment was not found in the P&O source, so the variant " + ...
          "would have been identical to nominal. The block has been rewritten " + ...
          "upstream -- re-read it before trusting any variant result.");
end
chart.Script = new;
end
