function mdlPath = buildDCLinkLoop()
%BUILDDCLINKLOOP Construct the DC-link voltage loop model from scratch.
%
%   mdlPath = buildDCLinkLoop() deletes any existing DCLinkLoop.slx, rebuilds it
%   block by block, and saves it. Returns the full path to the saved model.
%
%   Why a build script instead of just committing the .slx?
%   An .slx is a binary zip. Two people editing it produce two files that cannot
%   be merged or diffed -- you can only pick one and lose the other's work. This
%   script is plain text: it diffs cleanly, it reviews in a pull request, and any
%   team member can regenerate an identical model from it. The .slx becomes a
%   build artifact, not a source file.
%
%   THE PLANT
%   A DC-link capacitor obeys      C * dVdc/dt = i_src - i_out
%   where i_src is current injected by the PV and wind stages, and i_out is
%   current the grid-side inverter pulls out. The controller regulates Vdc by
%   commanding i_out. The inner current loop is fast compared to this outer
%   voltage loop, so it is modelled as a first-order lag rather than in full.
%
%   See docs/DESIGN_NOTES.md for the sign convention and the tuning derivation.

mdl = "DCLinkLoop";
here = fileparts(mfilename("fullpath"));
mdlPath = fullfile(here, mdl + ".slx");

if bdIsLoaded(mdl)
    close_system(mdl, 0);
end
if isfile(mdlPath)
    delete(mdlPath);
end

new_system(mdl);
load_system(mdl);

%% Blocks ---------------------------------------------------------------------
% Positions are [left top right bottom] in pixels, laid out left to right so the
% signal flow reads like the block diagram in the design notes.

add_block("simulink/Sources/In1",  mdl + "/Vdc_ref", ...
    Position = [30 100 60 114], Port = "1");

add_block("simulink/Sources/In1",  mdl + "/i_src", ...
    Position = [30 300 60 314], Port = "2");

% Error convention: e = Vdc - Vdc_ref  (measured MINUS reference).
% Signs "-+" means input 1 (Vdc_ref) is subtracted and input 2 (Vdc) is added.
add_block("simulink/Math Operations/Sum", mdl + "/Error", ...
    Position = [120 95 140 115], Inputs = "-+");

add_block("simulink/Continuous/PID Controller", mdl + "/Voltage_PI", ...
    Position = [180 85 250 125], ...
    Controller = "PI", ...
    ControllerParametersSource = "internal", ...
    P = "P.ctrl.Kp", ...
    I = "P.ctrl.Ki", ...
    LimitOutput = "off", ...
    ExternalReset = "none", ...
    InitialConditionSource = "internal");

% The inverter cannot source unlimited current. This is a hard physical limit,
% modelled downstream of the controller exactly as it exists in hardware.
add_block("simulink/Discontinuities/Saturation", mdl + "/Current_Limit", ...
    Position = [290 90 330 120], ...
    UpperLimit = "P.ctrl.Imax", ...
    LowerLimit = "-P.ctrl.Imax");

% Inner current loop, collapsed to its dominant first-order behaviour.
add_block("simulink/Continuous/Transfer Fcn", mdl + "/Inner_Current_Loop", ...
    Position = [370 85 450 125], ...
    Numerator = "[1]", ...
    Denominator = "[P.plant.tau_i 1]");

% Capacitor current balance: i_cap = i_src - i_out
add_block("simulink/Math Operations/Sum", mdl + "/Cap_Current", ...
    Position = [500 295 520 315], Inputs = "+-");

add_block("simulink/Math Operations/Gain", mdl + "/Inv_C", ...
    Position = [560 290 600 320], Gain = "1/P.plant.C");

add_block("simulink/Continuous/Integrator", mdl + "/DC_Bus_Cap", ...
    Position = [640 285 680 325], InitialCondition = "P.plant.Vdc0");

add_block("simulink/Sinks/Out1", mdl + "/Vdc", ...
    Position = [740 298 770 312], Port = "1");

add_block("simulink/Sinks/Out1", mdl + "/i_out", ...
    Position = [740 158 770 172], Port = "2");

%% Connections ----------------------------------------------------------------
add_line(mdl, "Vdc_ref/1",            "Error/1",              autorouting = "on");
add_line(mdl, "Error/1",              "Voltage_PI/1",         autorouting = "on");
add_line(mdl, "Voltage_PI/1",         "Current_Limit/1",      autorouting = "on");
add_line(mdl, "Current_Limit/1",      "Inner_Current_Loop/1", autorouting = "on");
add_line(mdl, "Inner_Current_Loop/1", "Cap_Current/2",        autorouting = "on");
add_line(mdl, "i_src/1",              "Cap_Current/1",        autorouting = "on");
add_line(mdl, "Cap_Current/1",        "Inv_C/1",              autorouting = "on");
add_line(mdl, "Inv_C/1",              "DC_Bus_Cap/1",         autorouting = "on");
add_line(mdl, "DC_Bus_Cap/1",         "Vdc/1",                autorouting = "on");
add_line(mdl, "Inner_Current_Loop/1", "i_out/1",              autorouting = "on");

% The feedback path. This is what makes it a closed loop rather than a chain.
add_line(mdl, "DC_Bus_Cap/1",         "Error/2",              autorouting = "on");

%% Named, logged signals ------------------------------------------------------
% Naming a signal does two things: it makes the diagram readable, and it gives
% the test assertions a stable handle. A test that says logsout.get("Vdc") keeps
% working when someone moves a block; a test that indexes yout{1} does not.
nameAndLog(mdl, "Error",              1, "e");
nameAndLog(mdl, "Inner_Current_Loop", 1, "i_out");
nameAndLog(mdl, "DC_Bus_Cap",         1, "Vdc");

%% Solver and logging configuration -------------------------------------------
% Fixed-step is deliberate. A variable-step solver chooses its own time points,
% so two runs of the same model land on different samples and cannot be compared
% element by element. Regression diffing needs an identical time vector.
% LoadExternalInput is switched on here, in the model, and left alone afterwards.
% The harness then supplies the actual waveforms with setExternalInput. Setting
% it in both places raises "ExternalInput needs to be specified only once".
set_param(mdl, ...
    SolverType        = "Fixed-step", ...
    Solver            = "ode4", ...
    FixedStep         = "P.sim.dt", ...
    StopTime          = "P.sim.stopTime", ...
    LoadExternalInput = "on", ...
    SignalLogging     = "on", ...
    SignalLoggingName = "logsout", ...
    SaveOutput        = "on", ...
    OutputSaveName    = "yout", ...
    SaveTime          = "on", ...
    TimeSaveName      = "tout", ...
    SaveFormat        = "Dataset", ...
    ReturnWorkspaceOutputs = "on");

save_system(mdl, mdlPath);
close_system(mdl, 0);

fprintf("Built %s\n", mdlPath);
end

% -----------------------------------------------------------------------------
function nameAndLog(mdl, srcBlock, srcPort, sigName)
%NAMEANDLOG Give an output signal a name and mark it for logging.
%
%   Two different handles are involved and it matters which is which:
%     the LINE carries the signal Name,
%     the output PORT carries the DataLogging setting.
%   Setting DataLogging on the line handle errors out.
%
%   LimitDataPoints is forced off. Left on, Simulink keeps only the last 5000
%   samples, so the beginning of the run silently disappears and any assertion
%   about startup behaviour is checking the wrong data.
ph = get_param(mdl + "/" + srcBlock, "PortHandles");
port = ph.Outport(srcPort);
lh = get_param(port, "Line");

set_param(lh, Name = sigName);
set_param(port, ...
    DataLogging                = "on", ...
    DataLoggingNameMode        = "SignalName", ...
    DataLoggingLimitDataPoints = "off");
end
