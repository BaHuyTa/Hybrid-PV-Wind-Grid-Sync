function [res, out] = runIntegration(names, opts)
%RUNINTEGRATION  Run integration scenarios on intSystem and measure them.
%
%   res = runIntegration()                    every scenario in intScenarios
%   res = runIntegration(["nominal","cloud"])
%   res = runIntegration("nominal", Model="myIntSystem", Save=false)
%   res = runIntegration("weak_grid", Set={"sfs.cf0",0,"sfs.kSFS",0})   extra xp overrides
%
% Returns one metrics struct per scenario (see analyseIntegration) and saves
% each run's logs to <results>/<name>.mat for plotIntegration.
%
% The model must follow the naming contract in the lab manual: subsystems PV,
% Wind, Inverter, and logged signals v_dc, i_pv, i_wind, i_inv, inv_tlm,
% wind_tlm, Id_ref, theta_ideal, w_hat, E.
%
% Runs one scenario at a time by default: each loads ~2 GB, and this machine
% has ~8 GB free with MATLAB open. Parallel=true uses parsim.

arguments
    names = []
    opts.Model    (1,1) string  = "intSystem"
    opts.Parallel (1,1) logical = false
    opts.Save     (1,1) logical = true
    opts.Set      cell          = {}     % extra {"field.path", value} overrides, every scenario
end

P   = intPaths();
mdl = char(opts.Model);
% any model other than the reference saves to results/<model>/, so runs don't overwrite
if mdl ~= "intSystem", P.results = fullfile(P.results, mdl); end
if ~bdIsLoaded(mdl), load_system(fullfile(P.here, [mdl '.slx'])); end

scn = intScenarios(names);
for k = 1:numel(scn), scn(k).set = [scn(k).set, opts.Set]; end
in  = Simulink.SimulationInput.empty;
for k = 1:numel(scn)
    in(k) = makeInput(mdl, scn(k));
end

if opts.Parallel && numel(in) > 1
    out = parsim(in, 'ShowProgress','on', 'TransferBaseWorkspaceVariables','off', ...
        'SetupFcn', @() intPaths(), 'StopOnError','off');
else
    out = Simulink.SimulationOutput.empty;
    for k = 1:numel(in)
        t0 = tic;
        % Errors come back in out.ErrorMessage instead of throwing, so one bad
        % scenario doesn't throw away the ones already run.
        out(k) = sim(in(k), 'StopOnError','off'); %#ok<AGROW>
        fprintf('%-12s %.1f s simulated in %.0f s\n', scn(k).name, scn(k).T, toc(t0));
    end
end

if opts.Save && ~isfolder(P.results), mkdir(P.results); end
res = struct([]);
for k = 1:numel(out)
    if ~isempty(out(k).ErrorMessage)
        warning('runIntegration:failed', '%s failed: %s', scn(k).name, out(k).ErrorMessage);
        continue
    end
    r = analyseIntegration(out(k).logsout, scn(k));
    % Scenarios carry different fields (only protection runs have r.prot): pad, then join.
    % setdiff gives a column; transpose it, or `for` runs once on an empty 0x1 cell.
    if ~isempty(res)
        for f = setdiff(fieldnames(res), fieldnames(r))', r.(f{1}) = []; end
        for f = setdiff(fieldnames(r), fieldnames(res))', [res.(f{1})] = deal([]); end
        r = orderfields(r, res);
    end
    res = [res r]; %#ok<AGROW>
    if opts.Save
        logsout = out(k).logsout; s = scn(k); %#ok<NASGU>
        save(fullfile(P.results, s.name + ".mat"), 'logsout', 's', 'r', '-v7.3');
    end
end
end

function in = makeInput(mdl, s)
% Weather profiles on a 1 ms grid. The root inports have interpolation off,
% so a step lands exactly on its grid point instead of being smeared into a ramp.
t  = (0:1e-3:s.T)';
ds = Simulink.SimulationData.Dataset;
ds = ds.addElement(timeseries(s.G(t),      t), 'G');
ds = ds.addElement(timeseries(s.v_wind(t), t), 'v_wind');

% Start the turbine settled at v_wind0, so the run isn't spent spinning up.
% Same derivation as windParams' own initial-condition block.
wp = windParams();
wp = rmfield(wp, {'li_inv','Cp'});
wp.v_init      = s.v_wind0;
wp.w_init      = wp.lam_opt*wp.v_init/wp.R;
wp.V_rect_init = 1.35*(wp.p*wp.w_init*wp.lam_pm)*sqrt(3)/sqrt(2);
wp.d_init      = 1 - wp.V_rect_init/wp.V_dc;

% Scenario overrides of intParams, e.g. {"trip.t", 0.5, "pcc.grid.t", 0.5}:
% breaker and trip timings live in xp, so a scenario sets them here.
xp = intParams();
for j = 1:2:numel(s.set)
    f  = strsplit(char(s.set{j}), '.');
    xp = setfield(xp, f{:}, s.set{j+1}); %#ok<SFLD>
end

in = Simulink.SimulationInput(mdl);
in = in.setVariable('xp', xp, 'Workspace', mdl);
% The settings the scripts rely on, forced here so a model that saved them
% differently still produces the same logs.
in = in.setModelParameter('StopTime', num2str(s.T), ...
    'LoadExternalInput','on', 'ExternalInput','ds', ...
    'SignalLogging','on', 'SignalLoggingName','logsout', 'ReturnWorkspaceOutputs','on');
in = in.setVariable('ds', ds);
in = in.setVariable('wp', wp, 'Workspace', mdl);
in = in.setBlockParameter([mdl '/PV/Solar Panel'], 'CellTempC', num2str(s.T_cell));
for j = 1:3:numel(s.block)
    in = in.setBlockParameter([mdl '/' char(s.block{j})], char(s.block{j+1}), char(s.block{j+2}));
end
end
