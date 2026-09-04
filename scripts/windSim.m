function [tl, logs] = windSim(t, v_wind, opts)
%WINDSIM  Run one wind-branch scenario on the averaged model.
%
%   tl = windSim(t, v_wind)
%   tl = windSim(t, v_wind, opts)
%
% Drives models/wind/windPlantAvg.slx with a wind profile and returns the
% telemetry bus as a struct of timeseries (omega_m, lambda, Cp, P_mech, P_dc,
% duty, mppt_state). The second output carries the logged internal signals
% (V_rect, i_L), which the telemetry contract does not expose.
%
% The DC link is represented as a stiff voltage source at wp.V_dc. That is the
% correct stand-in here: AC-coupled, the wind branch feeds its own DC link
% (DC link 2), which inverter 2's voltage loop holds at wp.V_dc. The capacitor
% is owned by the integration model (Hoang), and the whole point of the
% bandwidth separation argument is that the wind branch sees the link as
% constant.
%
% opts fields (all optional):
%   .model     model name                      (default 'windPlantAvg')
%   .v_dc      bus voltage, V                  (default wp.V_dc)
%   .enable    scalar or vector enable signal  (default 1)
%   .override  struct of windParams fields to override for this run
%
% Owner: Ba Huy Ta

arguments
    t       (:,1) double
    v_wind  (:,1) double
    opts    struct = struct()
end

wp  = windParams();
mdl = getfielddef(opts, 'model',  'windPlantAvg');
vdc = getfielddef(opts, 'v_dc',   wp.V_dc);
en  = getfielddef(opts, 'enable', 1);

% models/wind must be on the path or the windLib library links cannot resolve.
mdlDir = fullfile(windRoot(), 'models', 'wind');
if ~contains([path pathsep], [mdlDir pathsep])
    addpath(mdlDir);
end
if ~bdIsLoaded(mdl)
    load_system(fullfile(mdlDir, [mdl '.slx']));
end

if isscalar(vdc), vdc = vdc*ones(size(t)); end
if isscalar(en),  en  = en *ones(size(t)); end

ds = Simulink.SimulationData.Dataset;
ds = ds.addElement(timeseries(v_wind, t), 'v_wind');
ds = ds.addElement(timeseries(vdc,    t), 'v_dc');
ds = ds.addElement(timeseries(en,     t), 'enable');

in = Simulink.SimulationInput(mdl);
in = in.setModelParameter('StopTime', num2str(t(end)), ...
                          'LoadExternalInput','on', 'ExternalInput','ds', ...
                          'SaveOutput','on', 'SaveFormat','Dataset', ...
                          'SignalLogging','on', 'SignalLoggingName','logsout');
in = in.setVariable('ds', ds);

% Parameter overrides go into the MODEL workspace, where the blocks resolve wp.
% Function handles cannot survive into a block parameter, so strip them.
ov = getfielddef(opts, 'override', struct());
wpm = rmfield(wp, {'li_inv','Cp'});
f = fieldnames(ov);
for k = 1:numel(f)
    wpm.(f{k}) = ov.(f{k});
end
in = in.setVariable('wp', wpm, 'Workspace', mdl);

out = sim(in);
tl  = out.yout{2}.Values;      % the wind_tlm bus
logs = out.logsout;
end

% -------------------------------------------------------------------------
function v = getfielddef(s, name, default)
if isfield(s, name) && ~isempty(s.(name))
    v = s.(name);
else
    v = default;
end
end

function r = windRoot()
% Repo root, resolved from this file's own location - so the scripts work
% regardless of the current folder.
r = fileparts(fileparts(mfilename('fullpath')));
end
