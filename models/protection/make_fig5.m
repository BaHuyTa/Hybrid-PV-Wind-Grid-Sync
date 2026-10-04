function make_fig5()
%MAKE_FIG5 Regenerate the SFS on/off comparison figure.
%   Runs the matched-load islanding case twice - once with the anti-islanding
%   scheme disabled, once enabled - and plots the PCC frequency for both.
%   This is the principal evidence for success criterion SC5.
%
%   Colours are set explicitly and the figure is created invisible, so the
%   output does not depend on the MATLAB desktop theme. Do not add a call to
%   theme() here: it can block the session when driven non-interactively.
%
%   Usage:
%       make_fig5
%
%   Writes results/fig5_sfs_on_vs_off.png
%
%   See also PROTECTIONPARAMS, PROTECTION_FIGURES

mdl  = 'SFS';
here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(here));
addpath(here);
outdir = fullfile(root,'results');
if ~isfolder(outdir), mkdir(outdir); end

pp = protectionParams();
assignin('base','pp',pp);
if ~bdIsLoaded(mdl), load_system(fullfile(here,[mdl '.slx'])); end

% make sure the two signals we plot are logged
tagSignal(mdl, 'SFS:69', 'f_est');    % ClampBand output  (frequency estimate)
tagBlockOut(mdl, 'TripLogic', 'trip');   % relay output
set_param(mdl,'SignalLogging','on','SignalLoggingName','logsout');

b_cf0  = Simulink.ID.getFullName('SFS:38');   % Constant chopping factor
b_kSFS = Simulink.ID.getFullName('SFS:35');   % Gain (kSFS)

inOff = Simulink.SimulationInput(mdl);
inOff = inOff.setBlockParameter(b_cf0,'Value','0', b_kSFS,'Gain','0');
inOn  = Simulink.SimulationInput(mdl);

fprintf('running SFS disabled...\n');  outOff = sim(inOff);
fprintf('running SFS enabled...\n');   outOn  = sim(inOn);

plotComparison(outOff, outOn, pp, outdir);
end

% ---------------------------------------------------------------------
function tagSignal(mdl, sid, name)
ph = get_param(Simulink.ID.getFullName(sid),'PortHandles');
set_param(ph.Outport(1),'DataLogging','on', ...
    'DataLoggingNameMode','Custom','DataLoggingName',name);
end

% ---------------------------------------------------------------------
function tagBlockOut(mdl, blkName, name)
%TAGBLOCKOUT Tag a block's first output, found by NAME rather than by SID.
%   SIDs do not survive a block being deleted and re-added, which happens
%   whenever TripLogic is re-linked to the library. The name does.
ph = get_param([mdl '/' blkName],'PortHandles');
set_param(ph.Outport(1),'DataLogging','on', ...
    'DataLoggingNameMode','Custom','DataLoggingName',name);
end

% ---------------------------------------------------------------------
function plotComparison(outOff, outOn, pp, outdir)
fOff = pick(outOff, 'f_est');
fOn  = pick(outOn,  'f_est');
trOn = pick(outOn,  'trip');

tTrip = trOn.Values.Time(find(double(trOn.Values.Data) > 0.5, 1));
tA = fOff.Values.Time;  fA = fOff.Values.Data;
tB = fOn.Values.Time;   fB = fOn.Values.Data;
keep = tB <= tTrip;                 % beyond the trip the inverter is off

% invisible figure: cannot block on rendering
fg = figure('Color','w','Position',[100 100 1000 480],'Visible','off', ...
            'InvertHardcopy','off');
ax = axes(fg); hold(ax,'on'); box(ax,'on');
set(ax, 'Color','w', 'XColor','k', 'YColor','k', ...
        'GridColor',[0.72 0.72 0.72], 'GridAlpha',0.9, ...
        'FontSize',11, 'LineWidth',1.0);

hA = plot(ax, tA, fA, 'LineWidth',2.0, 'Color',[0.00 0.45 0.74]);
hB = plot(ax, tB(keep), fB(keep), 'LineWidth',2.0, 'Color',[0.85 0.33 0.10]);
hT = plot(ax, tTrip, fB(find(keep,1,'last')), 'v', 'MarkerSize',12, ...
          'MarkerFaceColor',[0.10 0.70 0.25], 'MarkerEdgeColor','k');

yline(ax, pp.f_max, '--', sprintf('over-frequency trip  %g Hz', pp.f_max), ...
    'Color',[0.55 0 0.55], 'LineWidth',1.4, 'FontSize',10, ...
    'LabelHorizontalAlignment','left', 'LabelVerticalAlignment','bottom', ...
    'Interpreter','none');
yline(ax, pp.f_min, '--', sprintf('under-frequency trip  %g Hz', pp.f_min), ...
    'Color',[0.55 0 0.55], 'LineWidth',1.4, 'FontSize',10, ...
    'LabelHorizontalAlignment','left', 'LabelVerticalAlignment','top', ...
    'Interpreter','none');
xline(ax, pp.t_island, '--', 'grid disconnects', ...
    'Color',[0.25 0.25 0.25], 'LineWidth',1.4, 'FontSize',10, ...
    'LabelVerticalAlignment','bottom', 'LabelHorizontalAlignment','right');

grid(ax,'on');
xlim(ax, [0.8 3]);
ylim(ax, [46.5 53.5]);
xlabel(ax, 'Time (s)', 'Color','k', 'FontSize',12);
ylabel(ax, 'PCC frequency (Hz)', 'Color','k', 'FontSize',12);
title(ax, { 'Matched load (\DeltaP = \DeltaQ = 0, Q_f = 1) - the worst case for detection', ...
    sprintf('passive protection never trips;  SFS detects and disconnects in %.0f ms', ...
            1000*(tTrip - pp.t_island)) }, ...
    'Color','k', 'FontSize',12.5, 'FontWeight','bold');

lg = legend(ax, [hA hB hT], { ...
    sprintf('SFS disabled - settles at %.2f Hz, NOT DETECTED', fA(end)), ...
    'SFS enabled - frequency driven to the threshold', ...
    sprintf('trip at t = %.3f s', tTrip) }, ...
    'Location','east', 'FontSize',10.5, 'EdgeColor',[0.45 0.45 0.45]);
set(lg, 'TextColor','k', 'Color','w');

exportgraphics(fg, fullfile(outdir,'fig5_sfs_on_vs_off.png'), ...
    'Resolution',200, 'BackgroundColor','white');
close(fg);

fprintf('\nSFS disabled : settles %.2f Hz, no trip\n', fA(end));
fprintf('SFS enabled  : trip at %.4f s, detection %.4f s\n', tTrip, tTrip - pp.t_island);
fprintf('written: %s\n', fullfile(outdir,'fig5_sfs_on_vs_off.png'));
end

% ---------------------------------------------------------------------
function s = pick(out, name)
%PICK Logged signal by name, tolerant of a name carried by two signals.
%   protection_figures tags the FreqEstimator subsystem outport as "f_est"
%   and this script tags the ClampBand output inside it. They are the same
%   line, but get() then returns a Dataset rather than an element.
s = out.logsout.get(name);
if isa(s, 'Simulink.SimulationData.Dataset')
    s = s.getElement(1);
end
end
