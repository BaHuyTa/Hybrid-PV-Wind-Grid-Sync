function [tl, logs, out] = invSim(t, opts)
%INVSIM  Run one inverter-branch scenario on the switched model.
%
%   tl = invSim(t)
%   tl = invSim(t, opts)
%   [tl, logs, out] = invSim(t, opts)
%
% Drives models/inverter/invPlantSw.slx and returns the telemetry bus as a
% struct of timeseries (v_pole, v_phase, v_line, i_load, gates, theta, P_ac).
% The DC-side current is out.yout{1}.Values; the second output carries the
% logged internal signals, and the third the full SimulationOutput, which with
% opts.simscape_log holds out.simlog.
%
% Unlike windSim there is no driving profile argument: at this stage the branch
% has no reference input, only a bus voltage and an enable. Both live in opts.
% When the dq current loop lands, its reference becomes the second positional
% argument and this signature grows to match windSim's.
%
% The DC bus is a stiff voltage source at ip.V_dc. That is the correct stand-in:
% the bus is held there by this inverter's own DC-link voltage loop, which is
% not in this model yet, and the capacitor is owned by the integration model.
%
% opts fields (all optional):
%   .model         model name                       (default 'invPlantSw')
%   .v_dc          bus voltage, V, scalar or vector (default ip.V_dc)
%   .enable        scalar or vector enable signal   (default 1)
%   .override      struct of invParams fields to override for this run
%   .simscape_log  true to log every Simscape variable into out.simlog
%                  (costs memory, default false)
%
% Owner: Duc Pham

arguments
    t    (:,1) double
    opts struct = struct()
end

ip  = invParams();
mdl = getfielddef(opts, 'model',  'invPlantSw');

% Default value for each inport the model happens to have. Both fidelities are
% driven through this one function; the switched model takes v_dc and enable,
% the averaged one takes Id_ref and Iq_ref.
defaults = struct('v_dc', ip.V_dc, 'enable', 1, 'Id_ref', 0, 'Iq_ref', ip.Iq_ref);

% models/inverter must be on the path or the model workspace cannot resolve
% invParams().
mdlDir = fullfile(invRoot(), 'models', 'inverter');
if ~contains([path pathsep], [mdlDir pathsep])
    addpath(mdlDir);
end
if ~bdIsLoaded(mdl)
    load_system(fullfile(mdlDir, [mdl '.slx']));
end

ds = Simulink.SimulationData.Dataset;
inBlocks = find_system(mdl, 'SearchDepth', 1, 'BlockType', 'Inport');
portNo   = cellfun(@(b) str2double(get_param(b,'Port')), inBlocks);
[~, ord] = sort(portNo);
for k = ord(:).'
    name = get_param(inBlocks{k}, 'Name');
    if isfield(opts, name)
        v = opts.(name);
    elseif isfield(defaults, name)
        v = defaults.(name);
    else
        error('invSim:noInput', ...
              'Model %s has inport "%s" with no value in opts and no default.', mdl, name);
    end
    if isscalar(v), v = v*ones(size(t)); end
    ds = ds.addElement(timeseries(v(:), t), name);
end

in = Simulink.SimulationInput(mdl);
in = in.setModelParameter('StopTime', num2str(t(end)), ...
                          'LoadExternalInput','on', 'ExternalInput','ds', ...
                          'SaveOutput','on', 'SaveFormat','Dataset', ...
                          'SignalLogging','on', 'SignalLoggingName','logsout');
in = in.setVariable('ds', ds);
if getfielddef(opts, 'simscape_log', false)
    % Simscape keeps only the last 10 000 samples by default (10 ms at
    % Ts_power); an FFT window needs the whole run, so lift the limit.
    in = in.setModelParameter('SimscapeLogType','all', 'SimscapeLogName','simlog', ...
                              'SimscapeLogLimitData','off');
end

% Overrides go into the MODEL workspace, where the blocks resolve ip.
ipm = ip;
f = fieldnames(getfielddef(opts, 'override', struct()));
ov = getfielddef(opts, 'override', struct());
for k = 1:numel(f)
    ipm.(f{k}) = ov.(f{k});
end
in = in.setVariable('ip', ipm, 'Workspace', mdl);

out = sim(in);
tl  = out.yout{2}.Values;      % the inv_tlm bus

% logsout is for internals the telemetry contract does not expose. At this
% stage the bus carries everything measured, so nothing is marked for logging
% and Simulink creates no logsout. It becomes real when the LCL lands and the
% inverter-side and grid-side currents diverge.
if any(strcmp(out.who, 'logsout'))
    logs = out.logsout;
else
    logs = Simulink.SimulationData.Dataset;
end
end

% -------------------------------------------------------------------------
function v = getfielddef(s, name, default)
if isfield(s, name) && ~isempty(s.(name))
    v = s.(name);
else
    v = default;
end
end

function r = invRoot()
% Repo root (models/inverter/<this file> -> up three), so the scripts work
% regardless of the current folder.
r = fileparts(fileparts(fileparts(mfilename('fullpath'))));
end
