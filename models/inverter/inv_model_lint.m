% inv_model_lint.m
% Structural checks on the inverter models - the claims made about HOW they are
% built, tested the same way the harness tests what they DO. No simulation; runs
% in a few seconds. Same shape as models/wind/wind_model_lint.m.
%
%   1. CurrentLoop is a RESOLVED library link to invLib, never a copy. The wind
%      branch lost two weeks to an unlinked MPPT carrying a controller the
%      library had already fixed; this is the same failure mode.
%   2. invLib is locked, so it cannot be edited by accident from a model.
%   3. Each model's workspace is bound to invParams() - no dependency on
%      whatever happens to be in the base workspace.
%   4. No design parameter is a numeric literal. Every value that sizes the
%      bridge, the filter, the grid or the loop must be an ip.* reference. Only
%      the parameters this design actually sets are listed; Simscape blocks
%      carry dozens of thermal and tolerance defaults the model does not use,
%      and those are deliberately not flagged.
%   5. The interface and the telemetry bus match the contract the rest of the
%      team codes against. The harness reads the bus by name, so a silent
%      rename is a broken integration.
%
% Usage:
%   addpath(genpath('models'));
%   inv_model_lint
%
% Owner: Duc Pham

clear; clc;
lib = 'invLib';

% model -> {inports, outports, telemetry fields, library-linked blocks}
spec = { ...
 'invPlantSw',   {'v_dc','Id_ref','Iq_ref'}, {'i_dc','inv_tlm'}, ...
                 {'i_dq','i_dq_ref','v_dq_cmd','theta','i1_abc','i2_abc','v_abc'}, ...
                 {'CurrentLoop','Modulator_SVPWM','LCLFilter','Bridge'}; ...
 'invPlantAvg',  {'Id_ref','Iq_ref'}, {'i_dq','inv_tlm'}, ...
                 {'i_dq','i_dq_ref','v_dq_cmd','theta','i_abc_m','v_abc_m'}, ...
                 {'CurrentLoop','ACSide/LCLFilter'}; ...
 'invBridge120', {'v_dc','enable'}, {'i_dc','inv_tlm'}, ...
                 {'v_pole','v_phase','v_line','i_load','gates','theta','P_ac'}, {'Bridge'}};

designParams = containers.Map();
designParams('Constant')     = {'Value'};
designParams('DigitalClock') = {'SampleTime'};
designParams('UnitDelay')    = {'SampleTime'};
designParams('Gain')         = {'Gain'};
% Simscape blocks matched on their library block: parameter names collide
% across families, so only what this design sets is listed.
simscapeParams = { ...
    'Converters/Converter',  {'Vth','Vf','Ron','Goff','diode_Vf','diode_Ron'}; ...
    'RLC Assemblies/RLC',    {'R','L','C'}; ...
    'Sources/Voltage Source',{'vline_rms','freq','impedance_option','SShortCircuit','XR'}; ...
    'Solver Configuration',  {'LocalSolverSampleTime'}; ...
    'IGBT (Ideal',           {'Vth','Vf','Ron','Goff','diode_Vf','diode_Ron','diode_Goff'}};
% Masked (non-Simscape) blocks matched on MaskType.
maskParams = { ...
    'PID', {'P','I','SampleTime','UpperSaturationLimit','LowerSaturationLimit'}};
allow = {'Gain/Gain'};                 % the [3x3] line-voltage transform

fails = {}; npass = 0; tags = {'FAIL','PASS'};
say = @(ok, msg) fprintf('  [%s] %s\n', tags{ok+1}, msg);

%% ---- library ----------------------------------------------------------
if ~bdIsLoaded(lib), load_system(lib); end
fprintf('=== %s ===\n', lib);
ok = strcmp(get_param(lib,'Lock'), 'on');
say(ok, 'library is locked');
if ok, npass = npass+1; else, fails{end+1} = [lib ' unlocked']; end

%% ---- per model --------------------------------------------------------
for m = 1:size(spec,1)
    mdl = spec{m,1};
    if ~bdIsLoaded(mdl), load_system(mdl); end
    fprintf('=== %s ===\n', mdl);

    % 1. library links
    for b = 1:numel(spec{m,5})
        blk = [mdl '/' spec{m,5}{b}];
        leaf = spec{m,5}{b};                    % may be nested, e.g. ACSide/LCLFilter
        sl   = find(leaf == '/', 1, 'last');
        if isempty(sl), sl = 0; end
        leaf = leaf(sl+1:end);
        ok  = strcmp(get_param(blk,'LinkStatus'), 'resolved') && ...
              strcmp(get_param(blk,'ReferenceBlock'), [lib '/' leaf]);
        say(ok, sprintf('%s is a resolved link to %s/%s', spec{m,5}{b}, lib, leaf));
        if ok, npass = npass+1; else, fails{end+1} = blk; end %#ok<SAGROW>
    end

    % 3. model workspace
    mw = get_param(mdl, 'ModelWorkspace');
    ok = strcmp(mw.DataSource,'MATLAB Code') && contains(mw.MATLABCode,'invParams()');
    say(ok, 'model workspace is MATLAB code calling invParams()');
    if ok, npass = npass+1; else, fails{end+1} = [mdl ' workspace']; end

    % 4. design parameters are ip.* references
    blks = find_system(mdl, 'FollowLinks','on', 'LookUnderMasks','all', 'Type','Block');
    nlit = 0;
    for k = 1:numel(blks)
        % Skip anything nested INSIDE a masked block. Those internals belong to
        % whoever wrote the mask - the Discrete PID Controller's anti-windup
        % logic is built from Constant blocks holding 0, 1 and -1, and they are
        % structural, not design values. Blocks this project sets are never
        % inside a mask; the masked blocks themselves are still checked below.
        if insideMask(blks{k}), continue; end
        bt    = get_param(blks{k}, 'BlockType');
        names = {};
        if strcmp(bt, 'SimscapeBlock')
            ref = get_param(blks{k}, 'ReferenceBlock');
            hit = find(cellfun(@(f) contains(ref,f), simscapeParams(:,1)), 1);
            if ~isempty(hit), names = simscapeParams{hit,2}; end
        elseif isKey(designParams, bt)
            names = designParams(bt);
        end
        if isempty(names)
            try
                mt  = get_param(blks{k}, 'MaskType');
                hit = find(cellfun(@(f) contains(mt,f), maskParams(:,1)), 1);
                if ~isempty(hit), names = maskParams{hit,2}; end
            catch
            end
        end
        for p = 1:numel(names)
            try
                v = strtrim(get_param(blks{k}, names{p}));
            catch
                continue
            end
            isLiteral = ~isempty(regexp(v, '^[-+0-9.eE\[\] ]+$', 'once'));
            key = sprintf('%s/%s', bt, names{p});
            if isLiteral && ~any(strcmp(allow,key)) && ~any(strcmp(allow,[key '=' v]))
                nlit = nlit + 1;
                fprintf('      literal: %-50s %s = %s\n', blks{k}, names{p}, v);
            end
        end
    end
    say(nlit == 0, sprintf('design parameters reference ip.* (%d literal(s))', nlit));
    if nlit == 0, npass = npass+1; else, fails{end+1} = [mdl ' literals']; end

    ok = strcmp(strtrim(get_param(mdl,'FixedStep')), 'ip.Ts_power');
    say(ok, 'fixed step references ip.Ts_power');
    if ok, npass = npass+1; else, fails{end+1} = [mdl ' FixedStep']; end

    % 5. interface + telemetry contract
    have = portNames(mdl,'Inport');   ok = isequal(have, spec{m,2});
    say(ok, sprintf('inports are [%s]', strjoin(have,' ')));
    if ok, npass = npass+1; else, fails{end+1} = [mdl ' inports']; end

    have = portNames(mdl,'Outport');  ok = isequal(have, spec{m,3});
    say(ok, sprintf('outports are [%s]', strjoin(have,' ')));
    if ok, npass = npass+1; else, fails{end+1} = [mdl ' outports']; end

    ph  = get_param([mdl '/Telemetry'],'PortHandles');
    got = cell(1, numel(ph.Inport));
    for k = 1:numel(ph.Inport)
        l = get_param(ph.Inport(k),'Line');
        if l == -1, got{k} = '<unconnected>'; else, got{k} = get_param(l,'Name'); end
        if isempty(got{k}), got{k} = '<unnamed>'; end
    end
    ok = isequal(got, spec{m,4});
    say(ok, sprintf('telemetry bus is [%s]', strjoin(got,' ')));
    if ~ok, fprintf('      expected: [%s]\n', strjoin(spec{m,4},' ')); end
    if ok, npass = npass+1; else, fails{end+1} = [mdl ' telemetry']; end
end

fprintf('\n  %d/%d checks passed\n', npass, npass + numel(fails));
if ~isempty(fails)
    error('inv_model_lint:failed', 'Structural check failed: %s', strjoin(fails, ', '));
end

% -------------------------------------------------------------------------
function tf = insideMask(blk)
% True if any STRICT ancestor of blk carries a mask.
tf = false;
p  = get_param(blk, 'Parent');
while ~isempty(p) && ~strcmp(get_param(p,'Type'), 'block_diagram')
    try
        if ~isempty(get_param(p, 'MaskType')), tf = true; return; end
    catch
    end
    p = get_param(p, 'Parent');
end
end

function names = portNames(mdl, type)
b = find_system(mdl, 'SearchDepth', 1, 'BlockType', type);
n = cellfun(@(p) str2double(get_param(p,'Port')), b);
[~, i] = sort(n);
names = cellfun(@(p) get_param(p,'Name'), b(i), 'UniformOutput', false)';
end
