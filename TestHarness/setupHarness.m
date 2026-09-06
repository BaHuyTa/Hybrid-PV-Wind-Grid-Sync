function setupHarness(opts)
%SETUPHARNESS One-line setup for the DC-link test harness. Run this first.
%
%   setupHarness()                 add paths, redirect build artifacts, fix OneDrive
%   setupHarness(Toolkit = true)   also initialize the Simulink Agentic Toolkit
%
%   Run this once per MATLAB session before runAll, runtests, or model_test:
%
%       cd <...>\TestHarness
%       setupHarness
%
%   It does three things, each of which has bitten this project once already.
%
%   1. PATHS. addpath for config/inputs/run/models/tests. Without it you get
%      "Unrecognized function or variable 'runAll'" -- which is also what you
%      get from genpath("TestHarness") when you are already standing inside
%      TestHarness, because that looks for a nested folder of the same name.
%
%   2. BUILD ARTIFACTS OUT OF ONEDRIVE. Simulink defaults its cache and code
%      generation folders to pwd. This project lives in a OneDrive folder
%      shared with five other people, so a single model_test run dropped about
%      1.1 MB of binary caches (slprj/, slcov_output/, *.slxc) into the synced
%      tree -- churn that syncs to everyone and merges for nobody. This points
%      both folders at LOCALAPPDATA instead: still cached between sessions, so
%      builds stay fast, but never synced.
%
%   3. P IN THE BASE WORKSPACE. Every block in DCLinkLoop.slx references
%      P.ctrl.*, P.plant.* or P.sim.* rather than a literal, so the model
%      cannot compile unless P exists. runAll and the unittest suite hide this,
%      because runScenario injects P through SimulationInput.setVariable -- but
%      anything that compiles the model directly (model_test, opening it in the
%      editor, Update Diagram) needs P in the base workspace, and without it
%      fails with a bare "compilation failures" message that names no cause.
%
%   4. THE ONEDRIVE READ-ONLY FLAG. OneDrive sets the read-only attribute on
%      synced directories. Writes actually succeed, but fileattrib reports
%      UserWrite = 0, and Simulink Test believes it -- model_test fails with
%      Simulink:Harness:ExternalHarnessDirNotWritable even though nothing is
%      really locked. Clearing the flag is the documented workaround.

arguments
    opts.Toolkit (1,1) logical = false
    opts.Quiet   (1,1) logical = false
    opts.Variant (1,1) string  = "nominal"
end

root = string(fileparts(mfilename("fullpath")));

%% 1. Paths
addpath(fullfile(root, "config"), fullfile(root, "inputs"), ...
        fullfile(root, "run"),    fullfile(root, "models"), ...
        fullfile(root, "tests"), ...
        fullfile(root, "pv"),     fullfile(root, "pv", "tests"));

%% 2. Build artifacts outside the synced folder
local = getenv("LOCALAPPDATA");
if local == ""
    local = tempdir;   % fall back rather than silently writing into OneDrive
end
cacheDir = fullfile(local, "DCLinkHarness", "cache");
if ~isfolder(cacheDir)
    mkdir(cacheDir);
end
Simulink.fileGenControl("set", CacheFolder = cacheDir, CodeGenFolder = cacheDir);

%% 3. P in the base workspace, so the model can compile on its own
assignin("base", "P", harnessParams(opts.Variant));

%% 4. OneDrive read-only flag
% Cleared on root AND every subfolder, because Simulink Test checks the
% model's own folder and its parent separately -- fixing only one of them just
% moves the error message.
%
% filePermissions rather than fileattrib: the latter is deprecated as of
% R2026a. Assigning .Writable writes through to disk immediately.
try
    sub = dir(fullfile(root, "**"));
    sub = sub([sub.isdir] & ~ismember(string({sub.name}), [".", ".."]));
    folders = [root; unique(string(fullfile({sub.folder}, {sub.name})))'];

    perms = filePermissions(folders);
    notWritable = ~[perms.Writable];
    if any(notWritable)
        [perms(notWritable).Writable] = deal(true);
    end
catch ME
    warning("setupHarness:permissions", ...
            "Could not clear the read-only flag (%s). model_test may fail " + ...
            "with Simulink:Harness:ExternalHarnessDirNotWritable.", ME.message);
end

%% Optional: Simulink Agentic Toolkit
% Not on by default -- it is only needed for the model_* MCP tools, and it
% prints its own banner.
if opts.Toolkit
    satkPath = fullfile(getenv("USERPROFILE"), ".matlab", "agentic-toolkits", "simulink");
    if isfolder(satkPath)
        addpath(satkPath);
        evalin("base", "satk_initialize");
    else
        warning("setupHarness:noToolkit", ...
                "Simulink Agentic Toolkit not found at %s", satkPath);
    end
end

if ~opts.Quiet
    fprintf("Harness ready (P = %s). Build artifacts -> %s\n", ...
            opts.Variant, cacheDir);
    fprintf("  runAll                     console report\n");
    fprintf("  runAll(Report = true)      + HTML report in results/reports\n");
    fprintf("  runtests(""tests/tDCLinkLoop.m"")   spec + regression suite\n");
    fprintf("  runPVAll                   spec check on the PV stage\n");
end
end
