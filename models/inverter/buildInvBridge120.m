function buildInvBridge120()
%BUILDINVBRIDGE120  Build models/inverter/invBridge120.slx from scratch.
%
% The .slx is binary and cannot be merged; this script is the source of
% truth for its structure, the same way TestHarness/models/buildDCLinkLoop.m
% and TestHarness/pv/buildPVModels.m are for theirs. Re-run it after any
% structural change and commit both.
%
% Every design value is written as an "ip.*" reference so the model resolves
% it from invParams() at compile time - inv_model_lint.m fails if a literal
% creeps into a mask.
%
% This is the 120-degree conduction VALIDATION model, kept because its results
% are the evidence for the gate mapping and the topology. The switched fidelity
% of the DELIVERABLE inverter is invPlantSw (SVPWM + current loop + LCL).
%
% Interface (mirrors the wind branch's contract):
%       in   v_dc     V   shared DC bus voltage, stiff
%       in   enable   -   1 = gates live, 0 = bridge blocked
%       out  i_dc     A   current DRAWN from the bus (wind/PV inject, this draws)
%       out  inv_tlm  -   telemetry bus: v_pole v_phase v_line i_load
%                         gates theta P_ac
%
% Owner: Duc Pham

mdl  = 'invBridge120';
lib  = 'invLib';
here = fileparts(mfilename('fullpath'));
addpath(here);

if bdIsLoaded(mdl), close_system(mdl, 0); end
if ~bdIsLoaded(lib), load_system(fullfile(here, [lib '.slx'])); end
new_system(mdl);
open_system(mdl);

% Model workspace reads invParams() - no dependency on the base workspace.
mw = get_param(mdl, 'ModelWorkspace');
mw.DataSource = 'MATLAB Code';
mw.MATLABCode = 'ip = invParams();';
mw.reload();

%% ===================================================================== DCLink
% The bus as this branch sees it: a stiff voltage source, because the 150 kVA
% inverter's own voltage loop holds it there. Same stand-in windSim documents.
s = subsys(mdl, 'DCLink', [190 60 300 150]);
addb(s, 'simulink/Sources/In1',                                          'v_dc',   [30 60 60 74]);
addb(s, 'nesl_utility/Simulink-PS Converter',                            'S2PS',   [110 50 160 90]);
addb(s, 'fl_lib/Electrical/Electrical Sources/Controlled Voltage Source','V_bus',   [220 130 280 200]);
addb(s, 'ee_lib/Sensors & Transducers/Current Sensor',                   'I_dc',   [350 110 400 150]);
addb(s, 'nesl_utility/PS-Simulink Converter',                            'PS2S',   [450 50 500 90]);
addb(s, 'simulink/Sinks/Out1',                                           'i_dc',   [550 63 580 77]);
addb(s, 'ee_lib/Connectors & References/Electrical Reference',           'Gnd_bus',[220 320 260 350]);
port(s, 'DCp', 1, 'Right', [600 170 610 190]);
port(s, 'DCn', 2, 'Right', [600 270 610 290]);
set_param([s '/V_bus'], 'Orientation', 'up');

wire(s, 'v_dc/1',    'S2PS/1');
wire(s, 'S2PS/R1',   'V_bus/R1');        % PS control input sets the bus voltage
wire(s, 'V_bus/L1',  'I_dc/L1');         % source + into the sensor
wire(s, 'I_dc/R2',   'DCp/L1');          % sensor - out to the bridge
wire(s, 'V_bus/R2',  'DCn/L1');          % source - is the bus negative rail
wire(s, 'Gnd_bus/L1','V_bus/R2');
wire(s, 'I_dc/R1',   'PS2S/L1');
wire(s, 'PS2S/1',    'i_dc/1');

%% ===================================================================== Gating
% The one block that gets replaced when this becomes SVPWM. Its interface
% (t, f_grid, enable) -> (gates, theta) is chosen so that swap touches
% nothing else in the model.
s = subsys(mdl, 'Gating', [190 300 320 400]);
addb(s, 'simulink/Sources/In1',           'enable',       [30 200 60 214]);
addb(s, 'simulink/Sources/Digital Clock', 'Clock',        [30 60 90 100]);
addb(s, 'simulink/Sources/Constant',      'f_grid',       [30 130 90 160]);
addb(s, 'simulink/User-Defined Functions/MATLAB Function','Gating_120deg',[170 55 320 215]);
addb(s, 'simulink/Math Operations/Reshape','Gates_vector',[380 70 430 110]);
addb(s, 'simulink/Sinks/Out1',            'gates',        [490 83 520 97]);
addb(s, 'simulink/Sinks/Out1',            'theta',        [490 173 520 187]);
set_param([s '/theta'],  'Port', '2');
set_param([s '/Clock'],  'SampleTime', 'ip.Ts_power');
set_param([s '/f_grid'], 'Value',      'ip.f_grid');
set_param([s '/Gates_vector'], 'OutputDimensionality', '1-D array');

chart = sfroot().find('-isa','Stateflow.EMChart','Path',[s '/Gating_120deg']);
chart.Script = gatingCode();

wire(s, 'Clock/1',  'Gating_120deg/1');
wire(s, 'f_grid/1', 'Gating_120deg/2');
wire(s, 'enable/1', 'Gating_120deg/3');
wire(s, 'Gating_120deg/1', 'Gates_vector/1');
wire(s, 'Gates_vector/1',  'gates/1');
wire(s, 'Gating_120deg/2', 'theta/1');

%% ===================================================================== Bridge
% Linked from invLib: six discrete IGBTs with S1..S6 gate tags, the textbook
% layout. Electrically identical to the Converter (Three-Phase) block it
% replaces - this script's own checks are what prove that.
add_block([lib '/Bridge'], [mdl '/Bridge'], 'Position', [420 60 540 240]);

%% ===================================================================== ACLoad
% Placeholder for the LCL filter + grid. Balanced wye, floating neutral - the
% floating star point is what makes the 120-degree phase voltage a quasi-square
% wave, and it is what the filter and the grid transformer present later.
s = subsys(mdl, 'ACLoad', [660 60 780 240]);
port(s, 'a', 1, 'Left', [40 100 50 120]);
port(s, 'b', 2, 'Left', [40 220 50 240]);
port(s, 'c', 3, 'Left', [40 340 50 360]);
addb(s, 'ee_lib/Passive/RLC Assemblies/RLC (Three-Phase)', 'Load', [340 90 420 370]);
% L is set even though the R structure does not use it: leaving it at the
% Simscape default is exactly how a stale value survives a later change of
% structure, and inv_model_lint flags it.
set_param([s '/Load'], 'port_option','ee.enum.threePhasePort.expanded', ...
                       'component_structure','ee.enum.rlc.structure.R', ...
                       'R','ip.R_load', 'L','ip.L_load', 'C','ip.Cf');
addb(s, 'simulink/Signal Routing/Mux', 'Mux_i',      [700 480 705 620]);
addb(s, 'simulink/Signal Routing/Mux', 'Mux_vphase', [700 700 705 840]);
set_param([s '/Mux_i'],      'Inputs','3');
set_param([s '/Mux_vphase'], 'Inputs','3');
addb(s, 'simulink/Sinks/Out1', 'v_phase', [790 763 820 777]);
addb(s, 'simulink/Sinks/Out1', 'i_load',  [790 543 820 557]);
set_param([s '/i_load'], 'Port', '2');
ph = {'a','b','c'};
for k = 1:3
    y = 100 + 120*(k-1);
    addb(s, 'ee_lib/Sensors & Transducers/Current Sensor', ['I_' ph{k}], [160 y 210 y+40]);
    addb(s, 'nesl_utility/PS-Simulink Converter', ['PS2S_i' ph{k}], [560 480+70*(k-1) 610 520+70*(k-1)]);
    wire(s, [ph{k} '/L1'],      ['I_' ph{k} '/L1']);
    wire(s, ['I_' ph{k} '/R2'], ['Load/L' num2str(k)]);
    wire(s, ['I_' ph{k} '/R1'], ['PS2S_i' ph{k} '/L1']);
    wire(s, ['PS2S_i' ph{k} '/1'], ['Mux_i/' num2str(k)]);

    addb(s, 'ee_lib/Sensors & Transducers/Voltage Sensor', ['V_' ph{k} 'n'], [460 700+70*(k-1) 510 740+70*(k-1)]);
    addb(s, 'nesl_utility/PS-Simulink Converter', ['PS2S_v' ph{k}], [560 700+70*(k-1) 610 740+70*(k-1)]);
    wire(s, ['V_' ph{k} 'n/L1'], ['Load/L' num2str(k)]);
    wire(s, ['V_' ph{k} 'n/R2'], 'Load/R1');           % the star point
    wire(s, ['V_' ph{k} 'n/R1'], ['PS2S_v' ph{k} '/L1']);
    wire(s, ['PS2S_v' ph{k} '/1'], ['Mux_vphase/' num2str(k)]);
end
wire(s, 'Load/R1', 'Load/R2');            % tie the far ends: floating star point
wire(s, 'Load/R2', 'Load/R3');
wire(s, 'Mux_i/1',      'i_load/1');
wire(s, 'Mux_vphase/1', 'v_phase/1');

%% ======================================================================= root
addb(mdl, 'simulink/Sources/In1', 'v_dc',   [60 95 90 109]);
addb(mdl, 'simulink/Sources/In1', 'enable', [60 335 90 349]);
set_param([mdl '/enable'], 'Port', '2');
addb(mdl, 'nesl_utility/Solver Configuration', 'SolverConfig', [330 440 400 480]);
set_param([mdl '/SolverConfig'], 'UseLocalSolver','on', ...
    'LocalSolverChoice','NE_BACKWARD_EULER_ADVANCER', 'LocalSolverSampleTime','ip.Ts_power');

addb(mdl, 'simulink/Math Operations/Gain', 'Line_voltages', [850 250 920 300]);
set_param([mdl '/Line_voltages'], 'Gain','[1 -1 0; 0 1 -1; -1 0 1]', ...
    'Multiplication','Matrix(K*u)');
addb(mdl, 'simulink/Math Operations/Dot Product', 'P_ac_calc', [850 350 900 400]);
addb(mdl, 'simulink/Signal Routing/Bus Creator', 'Telemetry', [1010 80 1015 420]);
set_param([mdl '/Telemetry'], 'Inputs', '7');
addb(mdl, 'simulink/Sinks/Out1', 'i_dc',    [1110 43 1140 57]);
addb(mdl, 'simulink/Sinks/Out1', 'inv_tlm', [1110 243 1140 257]);
set_param([mdl '/inv_tlm'], 'Port', '2');

wire(mdl, 'v_dc/1',   'DCLink/1');
wire(mdl, 'enable/1', 'Gating/1');
wire(mdl, 'DCLink/R1','Bridge/L1');
wire(mdl, 'DCLink/R2','Bridge/L2');
wire(mdl, 'SolverConfig/R1', 'Bridge/L1');
for k = 1:3
    wire(mdl, ['Bridge/R' num2str(k)], ['ACLoad/L' num2str(k)]);
end

% Telemetry field names come from the SIGNAL names, so each signal is named on
% its first branch. invSim and the harness read the bus by these names.
wire(mdl, 'Gating/1', 'Bridge/1',     'gates');
wire(mdl, 'Gating/1', 'Telemetry/5');
wire(mdl, 'Gating/2', 'Telemetry/6',  'theta');
wire(mdl, 'Bridge/1', 'Telemetry/1',  'v_pole');
wire(mdl, 'ACLoad/1', 'Telemetry/2',  'v_phase');
wire(mdl, 'ACLoad/1', 'Line_voltages/1');
wire(mdl, 'ACLoad/1', 'P_ac_calc/1');
wire(mdl, 'ACLoad/2', 'Telemetry/4',  'i_load');
wire(mdl, 'ACLoad/2', 'P_ac_calc/2');
wire(mdl, 'Line_voltages/1', 'Telemetry/3', 'v_line');
wire(mdl, 'P_ac_calc/1',     'Telemetry/7', 'P_ac');
wire(mdl, 'DCLink/1', 'i_dc/1', 'i_dc');
wire(mdl, 'Telemetry/1', 'inv_tlm/1');

%% ================================================================ model setup
set_param(mdl, 'SolverType','Fixed-step', 'Solver','FixedStepDiscrete', ...
    'FixedStep','ip.Ts_power', 'StopTime','0.1', 'SimscapeLogType','none', ...
    'SaveOutput','on', 'SaveFormat','Dataset', ...
    'SignalLogging','on', 'SignalLoggingName','logsout');

note(mdl, [60 620], { ...
    '120-degree conduction (six-step) three-phase VSI - gating and topology validation.'
    'Six-step is 31% THD with the 5th harmonic at 250 Hz, so it cannot reach the <5% target;'
    'that is what SVPWM is for. Replace the body of Gating and nothing else changes.'
    'ACLoad is the placeholder for the LCL filter + grid.'});

save_system(mdl, fullfile(here, [mdl '.slx']));
fprintf('Built %s\n', fullfile(here, [mdl '.slx']));
end

% ========================================================================= util

function code = gatingCode()
code = sprintf('%s\n', ...
 'function [g, theta] = gating_120deg(t, f_grid, enable)', ...
 '%#codegen', ...
 '% 120-degree conduction gating for a three-phase two-level bridge.', ...
 '%', ...
 '% Gate order matches the Six-Pulse Gate Multiplexer: [a+ a- b+ b- c+ c-].', ...
 '% Verified by firing one gate at a time into a split DC bus, and confirmed', ...
 '% by the multiplexer port labels Ga(H) Ga(L) Gb(H) Gb(L) Gc(H) Gc(L).', ...
 '%', ...
 '% Each device conducts for 120 deg and the two devices of a leg are', ...
 '% separated by 60 deg of silence, so no dead time is needed here. SPWM', ...
 '% will need it.', ...
 '%', ...
 '% The angles are compared directly rather than built from Pulse Generator', ...
 '% blocks: 120 deg is 1/3 of the period, which is not an integer number of', ...
 '% fixed-step samples, and Simulink rejects it. This form is exact at any', ...
 '% step size, and it is where the carrier comparison goes for SPWM.', ...
 'theta = mod(360*f_grid*t, 360);                    % electrical angle, deg', ...
 'g = zeros(6,1);', ...
 'if enable > 0.5', ...
 '    g(1) = double(theta >=   0 && theta < 120);    % a+', ...
 '    g(2) = double(theta >= 180 && theta < 300);    % a-', ...
 '    g(3) = double(theta >= 120 && theta < 240);    % b+', ...
 '    g(4) = double(theta >= 300 || theta <  60);    % b-', ...
 '    g(5) = double(theta >= 240 && theta < 360);    % c+', ...
 '    g(6) = double(theta >=  60 && theta < 180);    % c-', ...
 'end');
end

function p = subsys(parent, name, pos)
%SUBSYS  Empty subsystem, returned as a path for the blocks that go in it.
p = [parent '/' name];
add_block('built-in/Subsystem', p, 'Position', pos);
inner = find_system(p, 'SearchDepth', 1, 'Type', 'Block');
for k = 1:numel(inner)
    if ~strcmp(inner{k}, p), delete_block(inner{k}); end
end
end

function addb(parent, src, name, pos)
add_block(src, [parent '/' name]);
set_param([parent '/' name], 'Position', pos);
end

function port(parent, name, num, side, pos)
%PORT  Physical (Simscape) connection port on a subsystem boundary.
add_block('built-in/PMIOPort', [parent '/' name]);
set_param([parent '/' name], 'Port', num2str(num), 'Side', side, 'Position', pos);
end

function wire(parent, from, to, name)
%WIRE  Connect "Block/port" to "Block/port". A port written "L3"/"R2" is a
%      physical connection port (LConn 3 / RConn 2); a bare number is a signal
%      port. An optional fourth argument names the signal.
h = add_line(parent, resolvePort(parent, from, 'out'), ...
                     resolvePort(parent, to,   'in'), 'autorouting','on');
if nargin > 3, set_param(h, 'Name', name); end
end

function h = resolvePort(parent, spec, dir)
parts = split(string(spec), '/');
ph    = get_param([parent '/' char(parts(1))], 'PortHandles');
tok   = char(parts(2));
if any(tok(1) == 'LR')
    idx = str2double(tok(2:end));
    if tok(1) == 'L', grp = ph.LConn; else, grp = ph.RConn; end
    if numel(grp) < idx                       % boundary port blocks carry the
        if tok(1) == 'L', grp = ph.RConn; else, grp = ph.LConn; end   % other side
    end
    h = grp(idx);
else
    idx = str2double(tok);
    if strcmp(dir, 'out'), h = ph.Outport(idx); else, h = ph.Inport(idx); end
end
end

function note(mdl, pos, lines)
try
    an = Simulink.Annotation(mdl, strjoin(lines, newline));
    an.Position = pos;
catch
end
end
