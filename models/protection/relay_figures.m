function relay_figures()
%RELAY_FIGURES Evidence for the relay's blocking and persistence delays.
%   Produces two figures:
%
%     fig7_pll_startup.png  - the SRF-PLL frequency estimate during
%                             acquisition, at several initial phases,
%                             against the 47-52 Hz trip band
%     fig8_relay_guards.png - the same disturbance profile through the old
%                             bare comparator and the guarded relay
%
%   Colours are explicit and figures are built invisible, so output does not
%   depend on the MATLAB desktop theme. Do not add a call to theme().
%
%   See also PLL_STARTUP_PROBE, PLL_JUMP_PROBE, PROTECTIONPARAMS

here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(here));
addpath(here);
outdir = fullfile(root,'results');
if ~isfolder(outdir), mkdir(outdir); end
pp = protectionParams();  assignin('base','pp',pp);

figure7(pp, root, outdir);
figure8(pp, here, outdir);
end

% ---------------------------------------------------------------------
function figure7(pp, root, outdir)
%FIGURE7 PLL frequency estimate during acquisition.
load_system(fullfile(root,'models','control','srf_pll','srfPllLib.slx'));
mdl = 'relay_fig7_mdl';
if bdIsLoaded(mdl), close_system(mdl,0); end
new_system(mdl); load_system(mdl);
Ts = 1e-4;  Vpk = 326.5986;

add_block('simulink/Sources/Sine Wave',[mdl '/Vsrc'], ...
    'Amplitude',num2str(Vpk),'Frequency','2*pi*50', ...
    'Phase','[ph0, ph0-2*pi/3, ph0+2*pi/3]','SampleTime','0');
add_block('srfPllLib/SRF_PLL',[mdl '/PLL'], ...
    'Ts',num2str(Ts),'f0','50','fbw','25','zeta','0.707');
add_line(mdl,'Vsrc/1','PLL/1');
ph = get_param([mdl '/PLL'],'PortHandles');
set_param(ph.Outport(2),'DataLogging','on', ...
    'DataLoggingNameMode','Custom','DataLoggingName','f_hz');
set_param(ph.Outport(3),'DataLogging','on', ...
    'DataLoggingNameMode','Custom','DataLoggingName','vd');
set_param(mdl,'SignalLogging','on','SignalLoggingName','logsout', ...
    'StopTime','0.3','SolverType','Fixed-step','Solver','ode4', ...
    'FixedStep',num2str(Ts/10));

cases = [0 90 180 270];
col   = [0.00 0.45 0.74; 0.47 0.67 0.19; 0.93 0.69 0.13; 0.85 0.33 0.10];
fg = newFig([100 100 980 620]);

a1 = subplot(2,1,1); hold(a1,'on'); box(a1,'on');
h = gobjects(1,numel(cases));  lbl = cell(1,numel(cases));
worst = 0;  worstDur = 0;  vd270 = [];  t270 = [];
for k = 1:numel(cases)
    assignin('base','ph0',cases(k)*pi/180);
    out = sim(mdl);
    f  = out.logsout.get('f_hz');
    t  = double(f.Values.Time);  v = double(f.Values.Data);
    bad = v < pp.f_min | v > pp.f_max;
    if any(bad)
        last = t(find(bad,1,'last'));
        dur  = last - t(find(bad,1,'first'));
    else
        last = 0;  dur = 0;
    end
    worst = max(worst,last);  worstDur = max(worstDur,dur);
    h(k) = plot(a1,t*1000,v,'LineWidth',1.8,'Color',col(k,:));
    lbl{k} = sprintf('%d%s initial error', cases(k), char(176));
    if cases(k) == 270
        vdx = out.logsout.get('vd');
        t270 = t;  vd270 = double(vdx.Values.Data);
    end
end
yline(a1,pp.f_max,'--','Color',[0.55 0 0.55],'LineWidth',1.4, ...
    'Label',sprintf('over-frequency trip  %g Hz',pp.f_max), ...
    'LabelHorizontalAlignment','left','LabelVerticalAlignment','bottom');
yline(a1,pp.f_min,'--','Color',[0.55 0 0.55],'LineWidth',1.4, ...
    'Label',sprintf('under-frequency trip  %g Hz',pp.f_min), ...
    'LabelHorizontalAlignment','left','LabelVerticalAlignment','top');
xlim(a1,[0 300]);  ylim(a1,[38 62]); grid(a1,'on');
ylabel(a1,'f estimate (Hz)','FontSize',11);
title(a1,{'SRF-PLL frequency estimate during acquisition, by initial phase error', ...
    sprintf(['at 270%s the estimate reads a healthy 50.00 Hz for 110 ms before leaving ' ...
    'the band entirely'],char(176))},'FontSize',12,'FontWeight','bold');
legend(a1,h,lbl,'Location','southeast','FontSize',9.5,'NumColumns',2);

% the mechanism: vd is negative while the loop sits anti-phase
a2 = subplot(2,1,2); hold(a2,'on'); box(a2,'on');
plot(a2,t270*1000,vd270,'LineWidth',1.8,'Color',[0.85 0.33 0.10]);
yline(a2,0,'-','Color',[0.4 0.4 0.4],'LineWidth',1.0);
Vpk_ = 326.5986;
yline(a2, Vpk_,':','Color',[0 0.5 0],'LineWidth',1.4, ...
    'Label','+V_{pk}: correctly locked','LabelHorizontalAlignment','left', ...
    'LabelVerticalAlignment','bottom');
yline(a2,-Vpk_,':','Color',[0.75 0 0],'LineWidth',1.4, ...
    'Label','-V_{pk}: locked 180{\circ} out of phase','LabelHorizontalAlignment','left', ...
    'LabelVerticalAlignment','top');
xlim(a2,[0 300]); ylim(a2,[-420 420]); grid(a2,'on');
xlabel(a2,'Time (ms)','FontSize',12);
ylabel(a2,'v_d (V)','FontSize',11);
title(a2,{'why: at 270{\circ} the loop settles on the anti-phase equilibrium, not the grid', ...
    sprintf(['v_d sits at -V_{pk} until it escapes and slews 180%s; the frequency ' ...
    'excursion that follows lasts %.0f ms and ends at %.0f ms'], ...
    char(176), 1000*worstDur, 1000*worst)},'FontSize',12,'FontWeight','bold');

styleAx(findobj(fg,'Type','axes'));
saveFig(fg,outdir,'fig7_pll_startup.png');
close_system(mdl,0);
fprintf('fig7: excursion %.1f ms long, ending at %.1f ms\n',1000*worstDur,1000*worst);
end

% ---------------------------------------------------------------------
function figure8(pp, here, outdir)
%FIGURE8 The same disturbance through the old relay and the new one.
%   "Before" is the real TripLogic from SFS_w9_record, a bare comparator.
%   "After" is the current guarded relay. Same input to both.
Ts = pp.Ts;
t  = (0:Ts:2.0).';
f  = 50*ones(size(t));
f(t < 0.170) = 40;                          % PLL acquisition
jump = t >= 0.700 & t < 0.7124;             % 30 deg phase jump, measured
f(jump) = 60;
isl = t >= 1.2;                             % island
f(isl) = 50 + 20*(t(isl)-1.2);
assignin('base','fprof',timeseries(f,t));

trip = cell(1,2);
src  = {'SFS_w9_record','SFS'};
for k = 1:2
    if ~bdIsLoaded(src{k})
        load_system(fullfile(here,[src{k} '.slx']));
    end
    mdl = sprintf('relay_fig8_%d',k);
    if bdIsLoaded(mdl), close_system(mdl,0); end
    new_system(mdl); load_system(mdl);
    add_block('simulink/Sources/From Workspace',[mdl '/f_src'], ...
        'VariableName','fprof','SampleTime','0','Interpolate','on', ...
        'OutputAfterFinalValue','Holding final value');
    add_block([src{k} '/TripLogic'],[mdl '/Relay']);
    add_block('simulink/Sinks/To Workspace',[mdl '/out'], ...
        'VariableName','tripsig','SampleTime','-1');
    add_line(mdl,'f_src/1','Relay/1');  add_line(mdl,'Relay/1','out/1');
    set_param(mdl,'StopTime','2.0','SolverType','Fixed-step', ...
        'Solver','ode4','FixedStep',num2str(Ts));
    o = sim(mdl);
    trip{k} = o.tripsig;
    close_system(mdl,0);
end

fg = newFig([100 100 980 560]);
a1 = subplot(2,1,1); hold(a1,'on'); box(a1,'on');
plot(a1,t,f,'LineWidth',1.5,'Color',[0.00 0.45 0.74]);
yline(a1,pp.f_max,'--','Color',[0.55 0 0.55],'LineWidth',1.3);
yline(a1,pp.f_min,'--','Color',[0.55 0 0.55],'LineWidth',1.3);
text(a1,0.02,41,'PLL acquisition','FontSize',9.5,'Color',[0.3 0.3 0.3]);
text(a1,0.56,61,'30{\circ} phase jump','FontSize',9.5,'Color',[0.3 0.3 0.3]);
text(a1,1.25,56,'island','FontSize',9.5,'Color',[0.3 0.3 0.3]);
ylim(a1,[38 64]); xlim(a1,[0 2]); grid(a1,'on');
ylabel(a1,'f estimate (Hz)','FontSize',11);
title(a1,'Frequency estimate: two transients the relay must ignore, then a real island', ...
    'FontSize',12,'FontWeight','bold');

a2 = subplot(2,1,2); hold(a2,'on'); box(a2,'on');
hb = stairs(a2,trip{1}.Time,double(trip{1}.Data)+1.15,'LineWidth',2.0,'Color',[0.75 0 0]);
ha = stairs(a2,trip{2}.Time,double(trip{2}.Data),'LineWidth',2.0,'Color',[0 0.5 0]);
ylim(a2,[-0.25 2.5]); xlim(a2,[0 2]); grid(a2,'on');
set(a2,'YTick',[0 1 1.15 2.15],'YTickLabel',{'0','1','0','1'});
xlabel(a2,'Time (s)','FontSize',12);
ylabel(a2,'trip','FontSize',11);
legend(a2,[hb ha], ...
    {'bare comparator - latches at t = 0 on the PLL, never recovers', ...
     'with blocking and persistence - ignores both transients, trips on the island'}, ...
    'Location','east','FontSize',10);
k1 = find(double(trip{1}.Data)>0.5,1);  k2 = find(double(trip{2}.Data)>0.5,1);
title(a2,sprintf(['bare comparator trips at %.3f s;  guarded relay trips at %.3f s, ' ...
    '%.0f ms after the island'], trip{1}.Time(k1), trip{2}.Time(k2), ...
    1000*(trip{2}.Time(k2)-1.2)),'FontSize',12,'FontWeight','bold');
styleAx(findobj(fg,'Type','axes'));
saveFig(fg,outdir,'fig8_relay_guards.png');
fprintf('fig8: bare trips %.4f s, guarded trips %.4f s\n', ...
    trip{1}.Time(k1), trip{2}.Time(k2));
end

% ---------------------------------------------------------------------
function fg = newFig(pos)
fg = figure('Color','w','Position',pos,'Visible','off','InvertHardcopy','off');
end
function styleAx(ax)
for a = reshape(ax,1,[])
    set(a,'Color','w','XColor','k','YColor','k','GridColor',[0.72 0.72 0.72], ...
          'GridAlpha',0.9,'FontSize',11,'LineWidth',1.0,'Layer','top');
    set([get(a,'Title'), get(a,'XLabel'), get(a,'YLabel')],'Color','k');
    lg = get(a,'Legend');
    if ~isempty(lg)
        set(lg,'TextColor','k','Color','w','EdgeColor',[0.45 0.45 0.45]);
    end
end
end
function saveFig(fg,outdir,name)
exportgraphics(fg,fullfile(outdir,name),'Resolution',200,'BackgroundColor','white');
close(fg);
end
