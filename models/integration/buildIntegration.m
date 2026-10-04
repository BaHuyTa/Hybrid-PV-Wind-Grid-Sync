function mdlPath = buildIntegration(opts)
%BUILDINTEGRATION  Build intSystem.slx: PV + wind + inverter on one 700 V bus.
%
%   mdlPath = buildIntegration()                  PLL stand-in  -> intSystem.slx
%   mdlPath = buildIntegration(PLL="aqib")        Aqib's SRF_PLL -> intSystem_aqibPLL.slx
%
% The scripted reference build. The committed intSystem.slx was built by hand in
% the Simulink GUI to the same design; checkBuild grades either against the
% reference numbers.
%
% HOW THE PIECES JOIN
% Every component model was built by its owner against a "stiff bus fixture":
% a root inport v_dc drives an ideal voltage source, and the current that source
% carries comes back out as i_dc. That's the integration contract:
%
%        v_dc  ---> [ component ] ---> i_dc
%
% So the integration doesn't rewire anyone's circuit. It closes the loop
% through the one thing none of them owns, the bus capacitor:
%
%        C * dv_dc/dt = i_pv + i_wind - i_inv
%
% The capacitor is an integrator, so v_dc is a STATE. It has no direct
% feedthrough, and that breaks what would otherwise be an algebraic loop (each
% component's i_dc depends instantly on v_dc).
%
% WHAT IS COPIED, FROM WHERE (snapshot origin/main @ c86f01c, 27 Sep 2026;
% the first build used 8861f09, and PV v2 differs only by an added pv_tlm outport)
%   PV        models/pv-v2/solarsimulink.slx    (Belal)  switched boost + P&O
%   Wind      models/wind/windPlantAvg.slx      (Huy)    averaged
%   Inverter  models/inverter/invPlantSw.slx    (Duc)    switched SVPWM bridge + LCL
% Copied as subsystems (copyContentsToSubsystem). invLib/windLib blocks stay
% LIBRARY LINKS, so Duc's and Huy's shared blocks aren't forked.
%
% WHAT HAD TO CHANGE INSIDE THE COPIES (and why - each is an ask for the owner)
%   PV   - no i_dc outport existed: added a Current Sensor in series with the
%          bus fixture.  -> ask Belal to add it, so it can be referenced not copied
%        - irradiance was a Constant block: replaced with an inport G.
%        - boost output capacitor Cout pre-charged to 700 V (was 0 V).
%        - its Solver Configuration switched to a LOCAL backward-Euler solver at
%          0.5 us, because the whole system now runs one fixed-step solver.
%   Inv  - GridAngle_ideal no longer drives the loop: the SRF-PLL stand-in does.
%          The ideal angle is kept and brought out as theta_ideal, to measure
%          the PLL against.
%   All  - the owners' signal logging switched off (at a 0.5 us step it would
%          log millions of points). Logging is re-enabled on the integration's
%          own signals, decimated. The owners' Scopes are left in place.

arguments
    opts.PLL (1,1) string {mustBeMember(opts.PLL, ["standin" "aqib"])} = "standin"
end
P    = intPaths();
here = P.here;
if opts.PLL == "aqib"
    addpath(fullfile(P.models, 'control', 'srf_pll'));   % srfPllLib (Aqib)
    mdl = 'intSystem_aqibPLL';
else
    mdl = 'intSystem';
end
mdlPath = fullfile(here, [mdl '.slx']);
if bdIsLoaded(mdl), close_system(mdl, 0); end
if isfile(mdlPath), delete(mdlPath); end
new_system(mdl);

%% ---- Model workspace: every owner's parameter file, loaded as-is ---------
mw = get_param(mdl, 'ModelWorkspace');
mw.DataSource = 'MATLAB Code';
mw.MATLABCode = sprintf([ ...
    'ip = invParams();\n' ...
    'wp = windParams();\n' ...
    'wp = rmfield(wp, {''li_inv'',''Cp''});   %% function handles cannot live on a block\n' ...
    'xp = intParams();\n']);
mw.reload();

%% ---- Solver: one fixed step for everything --------------------------------
% Each Simscape network keeps its own local solver (discrete), so the global
% solver only integrates the Simulink continuous states: the bus capacitor and
% the averaged wind model. A fixed-step explicit solver at 0.5 us is plenty.
set_param(mdl, 'SolverType','Fixed-step', 'Solver','ode3', 'FixedStep','xp.Ts', ...
    'StopTime','1', ...
    'SignalLogging','on', 'SignalLoggingName','logsout', ...
    'SaveOutput','off', 'SaveTime','off', 'SaveState','off', ...
    'ReturnWorkspaceOutputs','on', 'LoadExternalInput','on', 'ExternalInput','ds', ...
    'AlgebraicLoopMsg','error');

%% ---- Root inputs: the weather ----------------------------------------------
add_block('simulink/Sources/In1', [mdl '/G'],      'Position', [ 40  98  70 112]);
add_block('simulink/Sources/In1', [mdl '/v_wind'], 'Position', [ 40 298  70 312]);
set_param([mdl '/v_wind'], 'Port', '2');
% Hold each input sample rather than interpolating, so a weather STEP is a step.
set_param([mdl '/G'], 'Interpolate', 'off');
set_param([mdl '/v_wind'], 'Interpolate', 'off');
add_block('simulink/Sources/Constant', [mdl '/wind_enable'], 'Value','1', ...
    'Position', [ 40 340  70 360]);
add_block('simulink/Sources/Constant', [mdl '/Iq_ref'], 'Value','ip.Iq_ref', ...
    'Position', [620 560 680 580]);

%% ---- Components --------------------------------------------------------------
pv  = copyComponent(mdl, 'PV',       'solarsimulink', [160  60 330 180]);
wnd = copyComponent(mdl, 'Wind',     'windPlantAvg',  [160 260 330 380]);
inv = copyComponent(mdl, 'Inverter', 'invPlantSw',    [760 440 930 600]);

patchPV(pv);
patchInverter(inv, opts.PLL);
% Only exists once a Simscape block is in the model. Off: at 0.5 us it would
% log every network variable, gigabytes per simulated second.
set_param(mdl, 'SimscapeLogType','none');

%% ---- The DC bus: C dv/dt = i_pv + i_wind - i_inv ----------------------------
bus = [mdl '/DCBus'];
add_block('built-in/Subsystem', bus, 'Position', [480 200 600 320], ...
    'BackgroundColor', 'yellow');
add_block('simulink/Sources/In1',    [bus '/i_pv'],   'Position', [ 30  40  60  54]);
add_block('simulink/Sources/In1',    [bus '/i_wind'], 'Position', [ 30  90  60 104], 'Port','2');
add_block('simulink/Sources/In1',    [bus '/i_inv'],  'Position', [ 30 140  60 154], 'Port','3');
add_block('simulink/Math Operations/Sum', [bus '/net'], 'Inputs','++-', ...
    'IconShape','rectangular', 'Position', [120 60 150 130]);
add_block('simulink/Math Operations/Gain', [bus '/one_over_C'], 'Gain','1/xp.C_bus', ...
    'Position', [190 80 240 110]);
add_block('simulink/Continuous/Integrator', [bus '/C_bus'], ...
    'InitialCondition','xp.Vdc0', 'Position', [280 80 310 110]);
add_block('simulink/Sinks/Out1', [bus '/v_dc'], 'Position', [360 88 390 102]);
add_line(bus, 'i_pv/1',   'net/1');
add_line(bus, 'i_wind/1', 'net/2');
add_line(bus, 'i_inv/1',  'net/3');
add_line(bus, 'net/1', 'one_over_C/1');
add_line(bus, 'one_over_C/1', 'C_bus/1');
add_line(bus, 'C_bus/1', 'v_dc/1');

%% ---- DC-link voltage loop (STAND-IN for Aqib) ---------------------------
dcl = [mdl '/DCLinkLoop_standin'];
add_block('built-in/Subsystem', dcl, 'Position', [480 470 620 550], ...
    'BackgroundColor', 'orange');
add_block('simulink/Sources/In1',        [dcl '/v_dc'],   'Position', [ 30 48  60 62]);
add_block('simulink/Sources/Constant',   [dcl '/Vdc_ref'], 'Value','xp.Vdc_ref', ...
    'Position', [ 20 90 70 110]);
add_block('simulink/Math Operations/Sum', [dcl '/err'], 'Inputs','+-', ...
    'Position', [110 55 130 85]);
add_block('simulink/Discrete/Discrete PID Controller', [dcl '/PI_vdc'], ...
    'Position', [170 50 250 90]);
set_param([dcl '/PI_vdc'], 'Controller','PI', 'Form','Parallel', ...
    'SampleTime','xp.Ts_ctrl', 'P','xp.dc.Kp', 'I','xp.dc.Ki', ...
    'IntegratorMethod','Forward Euler', ...
    'LimitOutput','on', 'UpperSaturationLimit','xp.dc.Id_max', ...
    'LowerSaturationLimit','-xp.dc.Id_max', 'AntiWindupMode','clamping');
add_block('simulink/Sinks/Out1', [dcl '/Id_ref'], 'Position', [300 63 330 77]);
add_line(dcl, 'v_dc/1', 'err/1');
add_line(dcl, 'Vdc_ref/1', 'err/2');
add_line(dcl, 'err/1', 'PI_vdc/1');
add_line(dcl, 'PI_vdc/1', 'Id_ref/1');
set_param(dcl, 'Description', ...
    'STAND-IN for Aqib''s DC-link voltage loop. Same design as the TestHarness DCLinkLoop (Kp = C*wc), converted to Id by power balance. Replace with Aqib''s block; ports: in v_dc [V], out Id_ref [A pk].');

%% ---- Wiring --------------------------------------------------------------
L = @(s,d,name) nameLine(add_line(mdl, s, d, 'autorouting','smart'), name);
L('G/1',           'PV/2',       'G');
L('v_wind/1',      'Wind/1',     'v_wind');
L('wind_enable/1', 'Wind/3',     '');
L('PV/1',          'DCBus/1',    'i_pv');
L('Wind/1',        'DCBus/2',    'i_wind');
L('Inverter/1',    'DCBus/3',    'i_inv');
L('DCBus/1',       'PV/1',       'v_dc');
add_line(mdl, 'DCBus/1', 'Wind/2',  'autorouting','smart');
add_line(mdl, 'DCBus/1', 'Inverter/1', 'autorouting','smart');
add_line(mdl, 'DCBus/1', 'DCLinkLoop_standin/1', 'autorouting','smart');
L('DCLinkLoop_standin/1', 'Inverter/2', 'Id_ref');
L('Iq_ref/1',      'Inverter/3', 'Iq_ref');

% Telemetry: terminate into named outports so nothing dangles.
add_block('simulink/Sinks/Terminator', [mdl '/T_wind'],  'Position', [380 350 400 370]);
add_block('simulink/Sinks/Terminator', [mdl '/T_inv'],   'Position', [990 510 1010 530]);
add_block('simulink/Sinks/Terminator', [mdl '/T_theta'], 'Position', [990 560 1010 580]);
L('Wind/2',     'T_wind/1',  'wind_tlm');
L('Inverter/2', 'T_inv/1',   'inv_tlm');
L('Inverter/3', 'T_theta/1', 'theta_ideal');
% PV v2 (27 Sep) has its own telemetry bus as outport 2 (i_dc was set to port 1).
pvp = get_param(pv, 'PortHandles');
if numel(pvp.Outport) > 1
    add_block('simulink/Sinks/Terminator', [mdl '/T_pv'], 'Position', [380 130 400 150]);
    L('PV/2', 'T_pv/1', 'pv_tlm');
end

%% ---- Energy meters -------------------------------------------------------
% The bus currents are CHOPPED at 10 kHz (a boost diode or a bridge leg
% conducts only part of each period). Logged samples taken every 5 us are
% synchronous with the 100 us carrier, so their average is biased: the first
% run showed 110 kW in vs 117 kW out on a bus that wasn't moving. Integrate
% energy at the full 0.5 us step instead. Average power over any window is then
% exact: P = (E(t1) - E(t0)) / (t1 - t0).
met = [mdl '/Meters'];
add_block('built-in/Subsystem', met, 'Position', [760 240 880 360], 'BackgroundColor','lightBlue');
names = {'v_dc','i_pv','i_wind','i_inv','inv_tlm'};
for k = 1:5
    add_block('simulink/Sources/In1', [met '/' names{k}], 'Port', num2str(k), ...
        'Position', [30 30+50*(k-1) 60 44+50*(k-1)]);
end
for k = 2:4
    add_block('simulink/Math Operations/Product', [met '/p' num2str(k-1)], ...
        'Position', [120 30+50*(k-1) 150 60+50*(k-1)]);
    add_line(met, 'v_dc/1', sprintf('p%d/1', k-1), 'autorouting','smart');
    add_line(met, [names{k} '/1'], sprintf('p%d/2', k-1), 'autorouting','smart');
end
add_block('simulink/Signal Routing/Bus Selector', [met '/sel'], ...
    'OutputSignals', 'v_abc,i2_abc', 'Position', [100 230 105 270]);
add_block('simulink/Math Operations/Dot Product', [met '/p_ac'], 'Position', [140 235 170 265]);
add_line(met, 'inv_tlm/1', 'sel/1');
add_line(met, 'sel/1', 'p_ac/1'); add_line(met, 'sel/2', 'p_ac/2');
add_block('simulink/Signal Routing/Mux', [met '/mux'], 'Inputs','4', 'Position', [220 60 225 260]);
for k = 1:3, add_line(met, sprintf('p%d/1', k), sprintf('mux/%d', k), 'autorouting','smart'); end
add_line(met, 'p_ac/1', 'mux/4', 'autorouting','smart');
add_block('simulink/Continuous/Integrator', [met '/energy'], 'Position', [270 145 300 175]);
add_block('simulink/Sinks/Out1', [met '/E'], 'Position', [340 153 370 167]);
add_line(met, 'mux/1', 'energy/1'); add_line(met, 'energy/1', 'E/1');
set_param(met, 'Description', 'E = [E_pv E_wind E_inv_dc E_ac] in J. Measurement only - nothing feeds back.');
add_line(mdl, 'DCBus/1',    'Meters/1', 'autorouting','smart');
add_line(mdl, 'PV/1',       'Meters/2', 'autorouting','smart');
add_line(mdl, 'Wind/1',     'Meters/3', 'autorouting','smart');
add_line(mdl, 'Inverter/1', 'Meters/4', 'autorouting','smart');
add_line(mdl, 'Inverter/2', 'Meters/5', 'autorouting','smart');
add_block('simulink/Sinks/Terminator', [mdl '/T_E'], 'Position', [920 290 940 310]);
L('Meters/1', 'T_E/1', 'E');

%% ---- Logging: owners' logging off, integration signals on (decimated) -------
% Logging is a property of the output PORT, not the line.
ports = find_system(mdl, 'FindAll','on', 'LookUnderMasks','all', 'FollowLinks','on', ...
    'MatchFilter',@Simulink.match.allVariants, 'Type','port', 'PortType','outport');
for h = ports(:)'
    if strcmp(get_param(h,'DataLogging'),'on')
        try
            set_param(h, 'DataLogging','off');
        catch                               % inside a locked library link:
            fprintf('  logging left on (library link): %s\n', get_param(h,'Parent'));
        end
    end
end
logLine(mdl, 'DCBus',      1, 'fast');     % v_dc
logLine(mdl, 'PV',         1, 'fast');     % i_pv
logLine(mdl, 'Wind',       1, 'fast');     % i_wind
logLine(mdl, 'Inverter',   1, 'fast');     % i_inv
logLine(mdl, 'Inverter',   2, 'fast');     % inv_tlm (i1, i2, v_abc, i_dq, theta ...)
logLine(mdl, 'Wind',       2, 'slow');     % wind_tlm
logLine(mdl, 'DCLinkLoop_standin', 1, ''); % Id_ref (already at 100 us)
logLine(mdl, 'Inverter',   3, '');         % theta_ideal
logLine(mdl, 'Meters',     1, 'slow');     % E = [E_pv E_wind E_inv E_ac]
if opts.PLL == "aqib"
    logLine([mdl '/Inverter'], 'f_to_w', 1, '');
else
    logLine([mdl '/Inverter/PLL_standin'], 'w_hat', 1, '');
end
logLine([mdl '/PV'], 'PV Sensors', 1, 'slow');   % Ipv (panel)
logLine([mdl '/PV'], 'PV Sensors', 2, 'slow');   % Vpv (panel)
logLine([mdl '/PV'], 'MPPT Controller', 1, 'slow');   % duty

%% ---- Annotation and save -----------------------------------------------
note = Simulink.Annotation([mdl '/note']);
note.Text = sprintf(['intSystem - integration reference, built by buildIntegration.m.\n' ...
    'Components copied from origin/main @ c86f01c (27 Sep 2026). ORANGE = stand-in for Aqib. ' ...
    'YELLOW = the shared 700 V bus (C = 44 mF).']);
note.Position = [40 10 900 40];
save_system(mdl, mdlPath);
fprintf('Built %s\n', mdlPath);
end

%% ======================================================================
function s = copyComponent(mdl, name, src, pos)
% Copy a component model's whole root into a subsystem. Root inports and
% outports become the subsystem's ports, in the same order.
s = [mdl '/' name];
add_block('built-in/Subsystem', s, 'Position', pos);
load_system(src);
Simulink.BlockDiagram.copyContentsToSubsystem(src, s);
set_param(s, 'Description', sprintf('Copied from %s.slx (origin/main @ c86f01c). Owner file is the source of truth.', src));
end

function patchPV(pv)
% 1. Irradiance: Constant -> inport G (port 2; v_dc stays port 1).
c   = [pv '/Constant'];
pos = get_param(c, 'Position');
lh  = get_param(c, 'LineHandles');
delete_line(lh.Outport(1));
delete_block(c);
add_block('simulink/Sources/In1', [pv '/G'], 'Position', pos, 'Port', '2');
add_line(pv, 'G/1', 'Solar Panel/1');

% 2. Current into the bus: Current Sensor in series between the boost output
%    (Boost Converter LConn3 = p_out) and the fixture's + terminal.
b  = [pv '/Boost Converter'];
lh = get_param(b, 'LineHandles');
delete_line(lh.LConn(3));
bp = get_param([pv '/DC_link'], 'Position');
add_block('fl_lib/Electrical/Electrical Sensors/Current Sensor', [pv '/I_pv'], ...
    'Position', [bp(1)-90 bp(2)-80 bp(1)-50 bp(2)-40], 'Orientation','right');
add_line(pv, 'Boost Converter/LConn3', 'I_pv/LConn1', 'autorouting','smart');
add_line(pv, 'I_pv/RConn2', 'DC_link/LConn1', 'autorouting','smart');
add_block('nesl_utility/PS-Simulink Converter', [pv '/PS_Ipv'], ...
    'Position', [bp(1)-90 bp(2)-140 bp(1)-50 bp(2)-110], 'Unit','A');
add_line(pv, 'I_pv/RConn1', 'PS_Ipv/LConn1', 'autorouting','smart');
add_block('simulink/Sinks/Out1', [pv '/i_dc'], ...
    'Position', [bp(1)+20 bp(2)-132 bp(1)+50 bp(2)-118]);
add_line(pv, 'PS_Ipv/1', 'i_dc/1', 'autorouting','smart');
% i_dc is output 1, whatever else the owner's model brings out (PV v2 adds pv_tlm).
set_param([pv '/i_dc'], 'Port', '1');

% 3. Pre-charge the boost output capacitor to the bus voltage. Standalone, Cout
%    starts at 0 V across an ideal 700 V source, and the source just absorbs the
%    step. On a real capacitor bus the same step is a -7e8 A spike that dragged
%    v_dc to -6 kV in the first sample (found on the first integrated run). A
%    real converter pre-charges its bus before it connects, and so does this.
set_param([pv '/Boost Converter/Cout'], 'vc_specify','on', 'vc_priority','High', ...
    'vc','xp.Vdc0', 'vc_unit','V');

% 4. Local solver: the system runs one fixed-step solver, so this network gets
%    its own discrete backward-Euler solver at the inverter's 0.5 us.
sc = find_system(pv, 'SearchDepth',1, 'ReferenceBlock','nesl_utility/Solver Configuration');
set_param(sc{1}, 'UseLocalSolver','on', 'LocalSolverChoice','NE_BACKWARD_EULER_ADVANCER', ...
    'LocalSolverSampleTime','xp.Ts');
end

function patchInverter(inv, which)
% Drop the SRF-PLL in where Duc's README says Aqib's block goes: in place of
% GridAngle_ideal. The ideal angle is kept, brought out as theta_ideal, and
% used as the yardstick for the PLL.
%   which = "standin"  the orange stand-in (buildPLL below)
%   which = "aqib"     Aqib's library block srfPllLib/SRF_PLL (library link)
ga  = [inv '/GridAngle_ideal'];
pos = get_param(ga, 'Position');
lh  = get_param(ga, 'LineHandles');
dst = get_param(lh.Outport(1), 'DstPortHandle');   % CurrentLoop, Modulator, Telemetry
delete_line(lh.Outport(1));
set_param(ga, 'Position', pos + [0 120 0 120]);

if which == "aqib"
    pll = [inv '/SRF_PLL'];
    add_block('srfPllLib/SRF_PLL', pll, 'Position', pos, 'Ts','ip.Ts_ctrl', 'f0','ip.f_grid');
    % f_hz -> rad/s, logged as w_hat like the stand-in's; vd unused
    add_block('simulink/Math Operations/Gain', [inv '/f_to_w'], 'Gain','2*pi', ...
        'Position', pos + [170 30 90 -10]);
    add_block('simulink/Sinks/Terminator', [inv '/T_whaq'], 'Position', pos + [230 35 160 -15]);
    add_block('simulink/Sinks/Terminator', [inv '/T_vd'],   'Position', pos + [170 60 110 -5]);
    add_line(inv, 'SRF_PLL/2', 'f_to_w/1', 'autorouting','smart');
    set_param(add_line(inv, 'f_to_w/1', 'T_whaq/1', 'autorouting','smart'), 'Name', 'w_hat');
    add_line(inv, 'SRF_PLL/3', 'T_vd/1', 'autorouting','smart');
else
    pll = [inv '/PLL_standin'];
    buildPLL(pll, pos);
end
[~, pn] = fileparts(pll);
src = get_param(get_param(lh.Inport(1), 'SrcPortHandle'), 'Parent');
srcPort = get_param(get_param(lh.Inport(1), 'SrcPortHandle'), 'PortNumber');
add_line(inv, sprintf('%s/%d', get_param(src,'Name'), srcPort), [pn '/1'], 'autorouting','smart');
ph = get_param(pll, 'PortHandles');
for d = dst(:)'
    h = add_line(inv, ph.Outport(1), d, 'autorouting','smart');
end
set_param(h, 'Name', 'theta_pll');      % names the telemetry bus element too
add_block('simulink/Sinks/Out1', [inv '/theta_ideal'], 'Port','3', ...
    'Position', pos + [200 128 170 106]);
add_line(inv, 'GridAngle_ideal/1', 'theta_ideal/1', 'autorouting','smart');
end

function buildPLL(pll, pos)
% SRF-PLL:  v_abc -> Clarke -> Park(theta_hat) -> vq/Vm -> PI -> + w0 -> integrate
add_block('built-in/Subsystem', pll, 'Position', pos, 'BackgroundColor','orange');
set_param(pll, 'Description', ...
    'STAND-IN for Aqib''s SRF-PLL. Drop-in for GridAngle_ideal: in v_abc [V], out theta [rad]. 20 Hz, zeta 0.707 (xp.pll).');
a = @(lib, name, p, varargin) add_block(lib, [pll '/' name], 'Position', p, varargin{:});
a('simulink/Sources/In1', 'v_abc', [ 20 100  50 114]);
% Sample the measurement at the control rate - the PLL runs on the controller.
a('simulink/Discrete/Zero-Order Hold', 'ZOH', [ 80  95 110 120], 'SampleTime','xp.Ts_ctrl');
a('simulink/Math Operations/Gain', 'Clarke', [140 90 210 125], ...
    'Gain','(2/3)*[1 -1/2 -1/2; 0 sqrt(3)/2 -sqrt(3)/2]', 'Multiplication','Matrix(K*u)');
a('simulink/Signal Routing/Demux', 'ab', [240 90 245 125], 'Outputs','2');
a('simulink/Math Operations/Trigonometric Function', 'sin', [300 180 330 200], 'Operator','sin');
a('simulink/Math Operations/Trigonometric Function', 'cos', [300 220 330 240], 'Operator','cos');
% vq = -v_alpha*sin(th) + v_beta*cos(th)
a('simulink/Math Operations/Product', 'a_sin', [360 90 390 120]);
a('simulink/Math Operations/Product', 'b_cos', [360 140 390 170]);
a('simulink/Math Operations/Sum', 'vq', [420 110 440 150], 'Inputs','-+');
a('simulink/Math Operations/Gain', 'per_unit', [470 115 510 145], 'Gain','1/xp.pll.Vm');
a('simulink/Discrete/Discrete PID Controller', 'PI_pll', [540 110 610 150]);
set_param([pll '/PI_pll'], 'Controller','PI', 'Form','Parallel', ...
    'SampleTime','xp.Ts_ctrl', 'P','xp.pll.Kp', 'I','xp.pll.Ki', ...
    'IntegratorMethod','Forward Euler');
a('simulink/Sources/Constant', 'w0', [560 180 610 200], 'Value','xp.pll.w0');
a('simulink/Math Operations/Sum', 'w_hat', [640 120 660 160], 'Inputs','++');
% theta_hat = integral of w_hat, wrapped to [-pi, pi) like atan2. The discrete
% integrator block has no wrap option, so it's built from parts. Forward Euler:
%   theta(k+1) = wrap( theta(k) + Ts*w_hat(k) )
a('simulink/Math Operations/Gain', 'Ts', [690 125 730 155], 'Gain','xp.Ts_ctrl');
a('simulink/Math Operations/Sum', 'accum', [760 120 780 160], 'Inputs','++');
a('simulink/User-Defined Functions/Fcn', 'wrap', [810 125 890 155], 'Expr','u - 2*pi*floor((u + pi)/(2*pi))');
a('simulink/Discrete/Unit Delay', 'theta_int', [920 125 950 155], ...
    'SampleTime','xp.Ts_ctrl', 'InitialCondition','xp.pll.theta0');
% Same one-sample computation delay as GridAngle_ideal, so the PLL is a true
% drop-in for the baseline Duc tuned the current loop against.
a('simulink/Discrete/Unit Delay', 'sample_theta', [990 125 1020 155], ...
    'SampleTime','xp.Ts_ctrl', 'InitialCondition','xp.pll.theta0');
a('simulink/Sinks/Out1', 'theta', [1060 133 1090 147]);

l = @(s,d) add_line(pll, s, d, 'autorouting','smart');
l('v_abc/1','ZOH/1'); l('ZOH/1','Clarke/1'); l('Clarke/1','ab/1');
l('ab/1','a_sin/1'); l('sin/1','a_sin/2');
l('ab/2','b_cos/1'); l('cos/1','b_cos/2');
l('a_sin/1','vq/1'); l('b_cos/1','vq/2');
l('vq/1','per_unit/1'); l('per_unit/1','PI_pll/1');
l('PI_pll/1','w_hat/1'); l('w0/1','w_hat/2');
l('w_hat/1','Ts/1'); l('Ts/1','accum/1'); l('theta_int/1','accum/2');
l('accum/1','wrap/1'); l('wrap/1','theta_int/1');
l('theta_int/1','sin/1'); l('theta_int/1','cos/1');
l('theta_int/1','sample_theta/1'); l('sample_theta/1','theta/1');
ph = get_param([pll '/w_hat'], 'PortHandles');
set_param(get_param(ph.Outport(1),'Line'), 'Name', 'w_hat');
end

function nameLine(h, name)
if ~isempty(name), set_param(h, 'Name', name); end
end

function logLine(sys, blk, port, rate)
ph = get_param([sys '/' blk], 'PortHandles');
p  = ph.Outport(port);
set_param(p, 'DataLogging', 'on');
nm = get_param(get_param(p,'Line'), 'Name');
if isempty(nm), nm = sprintf('%s_%d', blk, port); end
set_param(p, 'DataLoggingNameMode','Custom', 'DataLoggingName', matlab.lang.makeValidName(nm));
if ~isempty(rate)
    xp = intParams();                  % decimation must be a literal integer
    set_param(p, 'DataLoggingDecimateData','on', ...
        'DataLoggingDecimation', num2str(xp.log.(rate)));
end
end
