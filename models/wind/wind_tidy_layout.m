% wind_tidy_layout.m
% Re-lays out the root of windPlantAvg / windPlantSw for readability.
%   * power path left-to-right as drawn lines
%   * shared signals (omega_m, enable, v_dc, ...) and telemetry taps via Goto/From
%   * header annotation
% Purely cosmetic: no block parameter, signal name or logging flag changes.
% Run once after structural edits; verify with wind_model_lint and windSim.
% Owner: Ba Huy Ta

addpath(genpath(fileparts(fileparts(fileparts(mfilename('fullpath'))))));

%% ---- windPlantAvg ---------------------------------------------------------
m = 'windPlantAvg'; load_system(m);
pos = { 'v_wind',[40 50 70 70]; 'v_dc',[40 330 70 350]; 'enable',[40 400 70 420]; ...
        'Aerodynamics',[150 50 270 160]; 'Drivetrain',[500 80 600 130]; ...
        'GenRectifier',[830 80 930 130]; 'BoostAvg',[1160 50 1280 160]; ...
        'i_dc',[1420 95 1450 115]; 'P_dc_calc',[800 350 840 390]; ...
        'MPPT',[1160 300 1280 440]; 'Telemetry',[1600 30 1610 330]; 'wind_tlm',[1680 170 1710 190]};
direct = {'v_wind:1->Aerodynamics:1', 'Aerodynamics:1->Drivetrain:1', ...
          'Drivetrain:1->GenRectifier:1', 'GenRectifier:1->BoostAvg:1', ...
          'BoostAvg:2->i_dc:1', 'P_dc_calc:1->MPPT:1', 'Telemetry:1->wind_tlm:1'};
hdr = sprintf(['windPlantAvg - averaged wind plant, 60 kW (Ba Huy Ta)\n' ...
    'wind v -> Cp(lambda) rotor -> single-mass shaft -> PMSG + diode bridge (algebraic) -> averaged boost -> DC bus\n' ...
    'Inputs: v_wind [m/s], v_dc [V] (measured bus), enable.  Output: i_dc [A] into the shared 700 V bus + wind_tlm bus.\n' ...
    'The DC-bus capacitor is NOT in here (owned by the DC-link loop). All numbers come from windParams() via the model workspace.\n' ...
    'Tags carry shared signals: omega_m/enable/v_dc feed several blocks; the telemetry bus taps signals from everywhere.']);
tidy(m, pos, direct, hdr);

%% ---- windPlantSw ----------------------------------------------------------
m = 'windPlantSw'; load_system(m);
pos = { 'v_wind',[40 50 70 70]; 'v_dc',[40 330 70 350]; 'enable',[40 400 70 420]; ...
        'Aerodynamics',[150 50 270 160]; 'PowerStage',[500 50 620 170]; ...
        'i_dc',[1420 95 1450 115]; 'P_dc_calc',[800 350 840 390]; ...
        'MPPT',[1160 300 1280 440]; 'PWM',[1560 340 1640 400]; ...
        'Telemetry',[1600 30 1610 330]; 'wind_tlm',[1680 170 1710 190]};
direct = {'v_wind:1->Aerodynamics:1', 'Aerodynamics:1->PowerStage:1', ...
          'PowerStage:4->i_dc:1', 'P_dc_calc:1->MPPT:1', 'Telemetry:1->wind_tlm:1'};
hdr = sprintf(['windPlantSw - switched wind plant, 60 kW (Ba Huy Ta)\n' ...
    'wind v -> Cp(lambda) rotor -> Simscape PMSG + diode bridge + boost (real switches, Ts_power) -> DC bus\n' ...
    'Same interface and same windParams() as windPlantAvg; used for THD and final validation (wind_fidelity_check, wind_thd_check).\n' ...
    'Aerodynamics and MPPT are library links to windLib - edit them there, never here.\n' ...
    'Tags carry shared signals (omega_m, enable, v_dc, gate) and the telemetry taps.']);
tidy(m, pos, direct, hdr);

%% ---- windLib --------------------------------------------------------------
load_system('windLib'); set_param('windLib','Lock','off');
fb = find_system('windLib','LookUnderMasks','all','MaskType','Stateflow');
for i = 1:numel(fb)
    ph = get_param(fb{i},'Ports'); n = max(ph(1),ph(2)); p = get_param(fb{i},'Position');
    set_param(fb{i},'Position',[p(1) p(2) p(1)+120 p(2)+max(30*n+20,60)]);
end
Simulink.BlockDiagram.arrangeSystem('windLib/Aerodynamics');
Simulink.BlockDiagram.arrangeSystem('windLib/MPPT');
set_param('windLib/Aerodynamics','Position',[150 60 270 170]);
set_param('windLib/MPPT','Position',[400 60 520 200]);
delete(find_system('windLib','FindAll','on','SearchDepth',1,'Type','annotation'));
a = Simulink.Annotation('windLib/Annotation');
a.Text = sprintf(['windLib - blocks shared by windPlantAvg and windPlantSw so the two fidelities cannot drift.\n' ...
    'Aerodynamics: Cp(lambda, beta=0) Heier form, T_aero = P_mech / omega_m.\n' ...
    'MPPT: wp.mppt_mode selects P&O (0) or optimal torque control (1, default) with an inner PI current loop.\n' ...
    'Library is locked; wind_model_lint checks that.']);
a.Position = [150 220 700 300]; a.FontSize = 10;
set_param('windLib','Lock','on');
disp('layout done - run wind_model_lint, then save_system on all three');

%% =========================================================================
function tidy(m, pos, direct, hdr)
% --- inside the local subsystems: MATLAB Function blocks big enough for their
%     port labels, then Simulink's auto-arrange (good enough one level down)
fb = find_system(m,'LookUnderMasks','all','FollowLinks','off','MaskType','Stateflow');
for i = 1:numel(fb)
    ph = get_param(fb{i},'Ports'); n = max(ph(1),ph(2)); p = get_param(fb{i},'Position');
    set_param(fb{i},'Position',[p(1) p(2) p(1)+120 p(2)+max(30*n+20,60)]);
end
for s = find_system(m,'SearchDepth',1,'BlockType','SubSystem','LinkStatus','none')'
    % NEVER auto-arrange a Simscape subsystem: arrangeSystem has been seen to split a
    % shared physical node (PowerStage ground rail, 9 Sep 2026). Signal-only subsystems are safe.
    if ~isempty(find_system(s{1},'FindAll','on','Type','port','PortType','connection')), continue; end
    Simulink.BlockDiagram.arrangeSystem(s{1});
end
for k = 1:size(pos,1), set_param([m '/' pos{k,1}], 'Position', pos{k,2}); end

% --- record every root connection: src, dst, name, logging ---------------
% (re-runnable: a From block is resolved back to the port feeding its Goto)
L = find_system(m,'FindAll','on','SearchDepth',1,'Type','line');
tagSrc = containers.Map;                       % tag -> source port handle
for h = L'
    dph = get(h,'DstPortHandle');
    for d = dph(dph > 0)'
        if strcmp(get_param(get(d,'Parent'),'BlockType'),'Goto')
            tagSrc(get_param(get(d,'Parent'),'GotoTag')) = get(h,'SrcPortHandle');
        end
    end
end
C = struct('sb',{},'sp',{},'db',{},'dp',{},'name',{},'log',{});
for h = L'
    sph = get(h,'SrcPortHandle'); dph = get(h,'DstPortHandle');
    if sph < 0, continue; end
    srcBlk = get(sph,'Parent'); nm = get(h,'Name');
    if strcmp(get_param(srcBlk,'BlockType'),'From')
        sph = tagSrc(get_param(srcBlk,'GotoTag')); srcBlk = get(sph,'Parent');
        nm = get(get(sph,'Line'),'Name');
    end
    for d = dph(dph > 0)'
        if strcmp(get_param(get(d,'Parent'),'BlockType'),'Goto'), continue; end
        c.sb = get_param(srcBlk,'Name'); c.sp = get(sph,'PortNumber');
        c.db = get_param(get(d,'Parent'),'Name');   c.dp = get(d,'PortNumber');
        c.name = nm; c.log = get_param(sph,'DataLogging');   % logging is a port property
        if ~any(arrayfun(@(x) strcmp(x.db,c.db) && x.dp==c.dp, C)), C(end+1) = c; end %#ok<AGROW>
    end
end
% --- delete all root lines, old Goto/From, old annotations ---------------
for h = find_system(m,'FindAll','on','SearchDepth',1,'Type','line')'
    try, delete_line(h); catch, end
end
for b = [find_system(m,'SearchDepth',1,'BlockType','Goto'); find_system(m,'SearchDepth',1,'BlockType','From')]'
    delete_block(b{1});
end
delete(find_system(m,'FindAll','on','SearchDepth',1,'Type','annotation'));

% --- rebuild ---------------------------------------------------------------
key = @(c) sprintf('%s:%d->%s:%d', c.sb, c.sp, c.db, c.dp);
srcKey = @(c) sprintf('%s:%d', c.sb, c.sp);
named = containers.Map;      % source port -> already carries its name
gotos = containers.Map;      % source port -> tag
for c = C
    tag = c.name; if isempty(tag), tag = c.sb; end
    sph = get_param([m '/' c.sb],'PortHandles'); sph = sph.Outport(c.sp);
    dph = get_param([m '/' c.db],'PortHandles'); dph = dph.Inport(c.dp);
    if any(strcmp(key(c), direct))
        h = add_line(m, sph, dph, 'autorouting','smart');
    else
        if ~isKey(gotos, srcKey(c))
            pp = get(sph,'Position'); hasDirect = any(startsWith(direct, [srcKey(c) '->']));
            off = 0; if hasDirect, off = 28; end
            g = add_block('simulink/Signal Routing/Goto', sprintf('%s/Goto_%s', m, tag), ...
                'GotoTag', tag, 'ShowName','off', 'Position', [pp(1)+35 pp(2)+off-10 pp(1)+105 pp(2)+off+10]);
            gotos(srcKey(c)) = tag;
            gph = get_param(g,'PortHandles');
            h = add_line(m, sph, gph.Inport(1), 'autorouting','smart');
        else
            h = -1;
        end
        pp = get(dph,'Position');
        f = add_block('simulink/Signal Routing/From', sprintf('%s/From_%s_%s%d', m, tag, c.db, c.dp), ...
            'GotoTag', tag, 'ShowName','off', 'Position', [pp(1)-110 pp(2)-10 pp(1)-40 pp(2)+10]);
        fph = get_param(f,'PortHandles');
        hf = add_line(m, fph.Outport(1), dph, 'autorouting','smart');
        if strcmp(c.db,'Telemetry') && ~isempty(c.name), set(hf,'Name',c.name); end
    end
    if h > 0 && ~isKey(named, srcKey(c))
        if ~isempty(c.name), set(h,'Name',c.name); end
        set_param(sph,'DataLogging',c.log);
        named(srcKey(c)) = true;
    end
end
a = Simulink.Annotation([m '/Header']); a.Text = hdr; a.Position = [40 480 900 570];
a.FontSize = 10; a.HorizontalAlignment = 'left';
set_param(m,'ZoomFactor','FitSystem');
end
