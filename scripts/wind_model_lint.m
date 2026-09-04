% wind_model_lint.m
% Structural checks on the wind models - the claims the spec makes about
% HOW the models are built, tested the same way the harness tests what they
% DO. No simulation; runs in a few seconds.
%
%   1. Every Aerodynamics and MPPT block in windPlantAvg and windPlantSw is a
%      RESOLVED library link to windLib. (On 4 Sep 2026 the averaged model's
%      MPPT turned out to be an unlinked copy carrying a controller the
%      library had already fixed. The spec had said "shared so they cannot
%      drift" for two weeks.)
%   2. Both models bind their model workspace to windParams() - no dependency
%      on whatever is in the base workspace.
%   3. windLib is locked, so it cannot be edited by accident from a model.
%   4. No design parameter is a numeric literal. Every value that sizes the
%      plant or the converter must be a wp.* reference. (The switched boost
%      diode sat at the Simscape default 0.3 ohm until 4 Sep: 7 W at 3 kW,
%      600 W at 30 kW.) The list of parameter names checked is explicit
%      below; Simscape blocks carry dozens of thermal/tolerance defaults that
%      the model does not use, and those are deliberately not flagged.
%
% Usage:
%   addpath(genpath('params'), genpath('scripts'), genpath('models'));
%   wind_model_lint
%
% Owner: Ba Huy Ta

clear; clc;
models  = {'windPlantAvg', 'windPlantSw'};
lib     = 'windLib';
libBlks = {'Aerodynamics', 'MPPT'};

% Parameters that size the plant or the converter, by block type. Anything
% here that evaluates to a bare number instead of a wp.* expression fails.
designParams = containers.Map();
designParams('Gain')                 = {'Gain'};
designParams('Constant')             = {'Value'};
designParams('Integrator')           = {'InitialCondition'};
designParams('UnitDelay')            = {'SampleTime'};
designParams('Saturate')             = {'UpperLimit', 'LowerLimit'};
designParams('SubSystem')            = {'rep_seq_t'};                  % PWM carrier period
% Simscape blocks are matched on their library block, because parameter
% names collide across families (a Diode's exponential-model 'RS' is not a
% PMSM's stator 'Rs'; a Rectifier's junction 'C' is not a Capacitor's 'c').
% Only the parameters the wind design actually sets are listed.
simscapeParams = { ...
    'PMSM',              {'Ld', 'Lq', 'L0', 'Rs', 'J', 'lam', 'pm_flux_linkage', 'nPolePairs', 'angular_velocity'}; ...
    'Passive/Inductor',  {'l', 'r', 'i_L'}; ...
    'Passive/Capacitor', {'c', 'r'}; ...
    'Converters/Diode',  {'Vf', 'Ron'}; ...
    'Rectifier',         {'Vf', 'Ron'}; ...
    'IGBT',              {'Vf', 'Ron'}};
% Literals that are structural, not design values.
allow = {'Switch/Threshold', 'Constant/Value=1', 'Constant/Value=0', ...
         'SubSystem/rep_seq_y'};                 % carrier SHAPE [1 0 1]; its period is wp.f_sw

fails = {}; npass = 0; tags = {'FAIL', 'PASS'};
say = @(ok, msg) fprintf('  [%s] %s\n', tags{ok + 1}, msg);

for m = 1:numel(models)
    mdl = models{m};
    if ~bdIsLoaded(mdl), load_system(mdl); end
    fprintf('=== %s ===\n', mdl);

    % 1. library links
    for b = 1:numel(libBlks)
        blk = [mdl '/' libBlks{b}];
        ok  = strcmp(get_param(blk, 'LinkStatus'), 'resolved') && ...
              strcmp(get_param(blk, 'ReferenceBlock'), [lib '/' libBlks{b}]);
        say(ok, sprintf('%s is a resolved link to %s/%s', libBlks{b}, lib, libBlks{b}));
        if ok, npass = npass + 1; else, fails{end+1} = blk; end %#ok<SAGROW>
    end

    % 2. model workspace bound to windParams()
    mw = get_param(mdl, 'ModelWorkspace');
    ok = strcmp(mw.DataSource, 'MATLAB Code') && contains(mw.MATLABCode, 'windParams()');
    say(ok, 'model workspace is MATLAB code calling windParams()');
    if ok, npass = npass + 1; else, fails{end+1} = [mdl ' workspace']; end

    % 4. design parameters are wp.* references, not literals
    blks = find_system(mdl, 'FollowLinks', 'off', 'LookUnderMasks', 'all', 'Type', 'Block');
    nlit = 0;
    for k = 1:numel(blks)
        bt = get_param(blks{k}, 'BlockType');
        if strcmp(bt, 'SimscapeBlock')
            ref = get_param(blks{k}, 'ReferenceBlock');
            hit = find(cellfun(@(f) contains(ref, f), simscapeParams(:, 1)), 1);
            if isempty(hit), continue; end
            names = simscapeParams{hit, 2};
        elseif isKey(designParams, bt)
            names = designParams(bt);
        else
            continue
        end
        for p = 1:numel(names)
            try
                v = strtrim(get_param(blks{k}, names{p}));
            catch
                continue                       % block does not have this parameter
            end
            isLiteral = ~isempty(regexp(v, '^[-+0-9.eE\[\] ]+$', 'once'));
            key = sprintf('%s/%s', bt, names{p});
            if isLiteral && ~any(strcmp(allow, key)) && ~any(strcmp(allow, [key '=' v]))
                nlit = nlit + 1;
                fprintf('      literal: %-45s %s = %s\n', blks{k}, names{p}, v);
            end
        end
    end
    say(nlit == 0, sprintf('design parameters reference wp.* (%d literal(s) found)', nlit));
    if nlit == 0, npass = npass + 1; else, fails{end+1} = [mdl ' literals']; end
end

% 3. library locked
if ~bdIsLoaded(lib), load_system(lib); end
fprintf('=== %s ===\n', lib);
ok = strcmp(get_param(lib, 'Lock'), 'on');
say(ok, 'library is locked');
if ok, npass = npass + 1; else, fails{end+1} = [lib ' unlocked']; end

fprintf('\n  %d/%d checks passed\n', npass, npass + numel(fails));
if ~isempty(fails)
    error('wind_model_lint:failed', 'Structural check failed: %s', strjoin(fails, ', '));
end
