%% RUNDEMO  See the integration results live, one section at a time.
%
% How to use: open this file in the MATLAB editor, click inside a section and
% press Ctrl+Enter (or "Run Section" on the Editor tab). Run section 0 first,
% once per MATLAB session. Every section after that is independent.
%
% Each section loads the saved run from results/intSystem_aqibPLL/ if it is
% there and pops the figures up (zoom, pan, data tips all work). If the run is
% missing (the .mat logs are not in git, so a fresh machine has none), it runs
% the simulation first; the time is given in the section title. Set
% RERUN = true to force a fresh simulation anyway.
%
% The same figures are saved as PNGs in results/intSystem_aqibPLL/figures/
% (for the report). Numbers and explanations: results/RESULTS.md.

%% 0. Setup (once per MATLAB session, ~10 s)
here = fileparts(mfilename('fullpath'));
if isempty(here), here = fileparts(matlab.desktop.editor.getActiveFilename); end
evalc("run(fullfile(here, '..', '..', 'TestHarness', 'setupHarness.m'))");   % path, caches, OneDrive flags
cd(here);  intPaths();
M      = "intSystem_aqibPLL";          % the integration model (Aqib's PLL, SFS, curtailment, fault)
RERUN  = false;                        % true = simulate even if saved results exist
res    = fullfile(here, 'results', M);
have   = @(names) all(arrayfun(@(n) isfile(fullfile(res, n + ".mat")), string(names)));
runIf  = @(names) ~have(names) || RERUN;
fprintf('Ready. Results folder: %s\n', res);

%% 1. A real day, four site loads (Mohammad W10) — runs ~45 min if not saved
% Gullen Range NSW, 6 Oct 2026, 06:00-14:00 (AEMO 5-min data), at 50 / 150 / 250 kW
% site load, plus 250 kW shed at 10:00. Two figures: the weather that went in, and
% the four cases side by side.
day = ["day_load_min","day_load_mid","day_load_max","day_shed"];
if runIf(day), runIntegration("day", Model=M, Parallel=true); end
plotDay(Model=M, Show=true);

%% 2. Grid fault ride-through — runs ~6 min if not saved
% A 220 ms fault at the PCC (0.15 pu left), cleared by the grid. Nothing may trip;
% bus < 800 V; power back within 1 s.
if runIf("grid_dip"), runIntegration("grid_dip", Model=M); end
plotFault("grid_dip", Model=M, Show=true);

%% 3. Normal operation: nominal, cloud, gust, over-rating, weak grid — ~15 min if not saved
% Power flow, DC bus, grid current and its spectrum for each.
normal = ["nominal","cloud","gust","over_rating","weak_grid"];
if runIf(normal), runIntegration(normal, Model=M, Parallel=true); end
plotIntegration(normal, Model=M, Show=true);

%% 4. Protection: trip, island, anti-islanding on its own — ~10 min if not saved
prot = ["trip","island","island_sfs"];
if runIf(prot), runIntegration(prot, Model=M, Parallel=true); end
plotProtection(prot, Model=M, Show=true);

%% 5. The numbers behind any run, as a table
% Change the name to any scenario above.
S = load(fullfile(res, "grid_dip.mat"), 'r');  disp(S.r)

%% 6. Open the model itself
open_system(fullfile(here, M + ".slx"));

%% 7. Close all the figures
close all
