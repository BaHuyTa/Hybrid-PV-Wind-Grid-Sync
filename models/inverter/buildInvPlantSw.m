function buildInvPlantSw()
%BUILDINVPLANTSW  Build models/inverter/invPlantSw.slx - the switched inverter.
%
% The switched fidelity of the deliverable inverter: dq current loop -> SVPWM
% -> two-level IGBT bridge -> LCL filter -> grid. This is the model THD is
% measured on; invPlantAvg is the averaged twin used to tune the loop, and
% invBridge120 is the earlier 120-degree topology validation.
%
% Linked from invLib, not copied: CurrentLoop, Modulator_SVPWM, LCLFilter.
%
% What is REAL here:   the current loop, the modulator (carrier + dead time),
%                      the bridge, the LCL, the grid.
% What is a STUB here: Modulator_SVPWM is Belal's block and GridAngle_ideal is
%                      Aqib's SRF-PLL. Both are marked; both get replaced.
%
% Interface:
%       in   v_dc     V   shared DC bus voltage, stiff
%       in   Id_ref   A   active current command    <- Aqib's DC voltage loop
%       in   Iq_ref   A   reactive current command
%       out  i_dc     A   current DRAWN from the bus
%       out  inv_tlm  -   telemetry bus
%
% Owner: Duc Pham

mdl  = 'invPlantSw';
lib  = 'invLib';
here = fileparts(mfilename('fullpath'));
addpath(here);

if bdIsLoaded(mdl), close_system(mdl, 0); end
if ~bdIsLoaded(lib), load_system(fullfile(here, [lib '.slx'])); end
new_system(mdl);
open_system(mdl);

mw = get_param(mdl, 'ModelWorkspace');
mw.DataSource = 'MATLAB Code';
mw.MATLABCode = 'ip = invParams();';
mw.reload();

%% ===================================================================== DCLink
s = subsys(mdl, 'DCLink', [180 60 300 160]);
addb(s, 'simulink/Sources/In1',                                           'v_dc',   [30 60 60 74]);
addb(s, 'nesl_utility/Simulink-PS Converter',                             'S2PS',   [110 50 160 90]);
addb(s, 'fl_lib/Electrical/Electrical Sources/Controlled Voltage Source', 'V_bus',  [220 130 280 200]);
addb(s, 'ee_lib/Sensors & Transducers/Current Sensor',                    'I_dc',   [350 110 400 150]);
addb(s, 'nesl_utility/PS-Simulink Converter',                             'PS2S',   [450 50 500 90]);
addb(s, 'simulink/Sinks/Out1',                                            'i_dc',   [550 63 580 77]);
port(s, 'DCp', 1, 'Right', [600 170 610 190]);
port(s, 'DCn', 2, 'Right', [600 270 610 290]);
set_param([s '/V_bus'], 'Orientation','up');
wire(s, 'v_dc/1','S2PS/1');   wire(s, 'S2PS/R1','V_bus/R1');
wire(s, 'V_bus/L1','I_dc/L1');  wire(s, 'I_dc/R2','DCp/L1');
wire(s, 'V_bus/R2','DCn/L1');
wire(s, 'I_dc/R1','PS2S/L1');   wire(s, 'PS2S/1','i_dc/1');

% The DC bus is NOT grounded here, and that is deliberate. The grid neutral is
% the single reference for the whole network. Ground the DC negative as well
% and the bridge's Vdc/2 common-mode offset sits directly across the filter
% inductors' few milliohms - a DC short drawing tens of kA, which is exactly
% what happened the first time this was built. A transformerless grid-tie DC
% bus floats; that is why the topology works at all.

%% ===================================================================== Bridge
s = subsys(mdl, 'Bridge', [420 60 540 240]);
addb(s, 'simulink/Sources/In1',          'gates', [30 480 60 494]);
addb(s, 'simulink/Signal Routing/Demux', 'Demux', [110 340 115 640]);
set_param([s '/Demux'], 'Outputs','6');
addb(s, 'ee_lib/Semiconductors & Converters/Converters/Six-Pulse Gate Multiplexer', ...
        'GateMux', [280 335 350 645]);
for k = 1:6
    y = 340 + 50*(k-1);
    addb(s, 'nesl_utility/Simulink-PS Converter', sprintf('S2PS_%d',k), [180 y-5 230 y+35]);
    wire(s, sprintf('Demux/%d',k),   sprintf('S2PS_%d/1',k));
    wire(s, sprintf('S2PS_%d/R1',k), sprintf('GateMux/L%d',k));
end
wire(s, 'gates/1','Demux/1');

addb(s, 'ee_lib/Semiconductors & Converters/Converters/Converter (Three-Phase)', ...
        'Converter', [450 60 570 280]);
set_param([s '/Converter'], ...
    'port_option','ee.enum.threePhasePort.expanded', ...
    'device_type','ee.enum.converters.switchingdevice.igbt', ...
    'diode_param','ee.enum.converters.protectiondiode.nodynamics', ...
    'Vth','ip.Vth_gate', 'Vf','ip.Vf_dev', 'Ron','ip.Ron_dev', 'Goff','ip.Goff_dev', ...
    'diode_Vf','ip.Vf_dev', 'diode_Ron','ip.Ron_dev', 'BlockMirror','on');
wire(s, 'GateMux/R1','Converter/L1');

port(s, 'DCp', 1, 'Left',  [40 100 50 120]);
port(s, 'DCn', 2, 'Left',  [40 200 50 220]);
port(s, 'a',   3, 'Right', [950 100 960 120]);
port(s, 'b',   4, 'Right', [950 170 960 190]);
port(s, 'c',   5, 'Right', [950 240 960 260]);
wire(s, 'DCp/L1','Converter/R1');
wire(s, 'DCn/L1','Converter/R2');
phn = {'a','b','c'};
for k = 1:3
    wire(s, ['Converter/L' num2str(k+1)], [phn{k} '/L1']);
end

%% =================================================================== GridSide
% Stiff grid at the PCC. Its impedance option is set EXPLICITLY - the block
% ships with a 1 MVA short-circuit level, which at 150 kVA is a weak grid and
% destabilises the current loop through the voltage feedforward.
s = subsys(mdl, 'GridSide', [900 60 1020 200]);
port(s, 'a', 1, 'Left', [40  60  50  80]);
port(s, 'b', 2, 'Left', [40 160  50 180]);
port(s, 'c', 3, 'Left', [40 260  50 280]);
addb(s, 'ee_lib/Connectors & References/Phase Splitter', 'Split_pcc', [220 60 260 280]);
addb(s, 'ee_lib/Sources/Voltage Source (Three-Phase)',   'Grid',      [360 100 430 240]);
set_param([s '/Grid'], 'vline_rms','ip.V_ll', 'freq','ip.f_grid', 'shift','0', ...
    'impedance_option','ip.grid_Z_opt', 'SShortCircuit','ip.S_sc', 'XR','ip.grid_XR');
addb(s, 'ee_lib/Connectors & References/Electrical Reference', 'Gnd_grid', [360 320 400 350]);
addb(s, 'ee_lib/Connectors & References/Electrical Reference', 'Gnd_meas', [300 620 340 650]);
addb(s, 'simulink/Signal Routing/Mux', 'Mux_v', [620 400 625 540]);
set_param([s '/Mux_v'], 'Inputs','3');
addb(s, 'simulink/Sinks/Out1', 'v_abc', [700 463 730 477]);
wire(s, 'Split_pcc/L1','Grid/R1');
wire(s, 'Gnd_grid/L1','Grid/L1');
phn = {'a','b','c'};
for k = 1:3
    p = phn{k};
    wire(s, [p '/L1'], ['Split_pcc/R' num2str(k)]);
    addb(s, 'ee_lib/Sensors & Transducers/Voltage Sensor', ['V_' p], [420 400+70*(k-1) 470 440+70*(k-1)]);
    addb(s, 'nesl_utility/PS-Simulink Converter', ['PS_v' p], [520 400+70*(k-1) 570 440+70*(k-1)]);
    wire(s, ['V_' p '/L1'], ['Split_pcc/R' num2str(k)]);
    wire(s, ['V_' p '/R2'], 'Gnd_meas/L1');
    wire(s, ['V_' p '/R1'], ['PS_v' p '/L1']);
    wire(s, ['PS_v' p '/1'], ['Mux_v/' num2str(k)]);
end
wire(s, 'Mux_v/1','v_abc/1');

%% ============================================================ GridAngle_ideal
% Stand-in for Aqib's SRF-PLL: the angle straight off the Clarke transform, no
% loop and no filter. Sampled at the control rate, which is also what breaks the
% angle path's algebraic loop.
s = subsys(mdl, 'GridAngle_ideal', [700 400 830 480]);
addb(s, 'simulink/Sources/In1', 'v_abc', [30 100 60 114]);
addb(s, 'simulink/User-Defined Functions/MATLAB Function', 'grid_angle', [150 60 300 160]);
chart = sfroot().find('-isa','Stateflow.EMChart','Path',[s '/grid_angle']);
chart.Script = gridAngleCode();
addb(s, 'simulink/Discrete/Unit Delay', 'sample_theta', [330 90 370 130]);
set_param([s '/sample_theta'], 'SampleTime','ip.Ts_ctrl');
addb(s, 'simulink/Sinks/Out1', 'theta', [420 103 450 117]);
wire(s, 'v_abc/1','grid_angle/1');
wire(s, 'grid_angle/1','sample_theta/1');
wire(s, 'sample_theta/1','theta/1');

%% ======================================================================= root
addb(mdl, 'simulink/Sources/In1', 'v_dc',   [60  95  90 109]);
addb(mdl, 'simulink/Sources/In1', 'Id_ref', [60 520  90 534]);
addb(mdl, 'simulink/Sources/In1', 'Iq_ref', [60 580  90 594]);
set_param([mdl '/Id_ref'],'Port','2'); set_param([mdl '/Iq_ref'],'Port','3');

add_block([lib '/CurrentLoop'],      [mdl '/CurrentLoop'],      'Position',[200 460 340 620]);
add_block([lib '/Modulator_SVPWM'],  [mdl '/Modulator_SVPWM'],  'Position',[400 460 520 560]);
add_block([lib '/LCLFilter'],        [mdl '/LCLFilter'],        'Position',[660 60 790 220]);

addb(mdl, 'nesl_utility/Solver Configuration', 'SolverConfig', [360 300 430 340]);
set_param([mdl '/SolverConfig'], 'UseLocalSolver','on', ...
    'LocalSolverChoice','NE_BACKWARD_EULER_ADVANCER', 'LocalSolverSampleTime','ip.Ts_power');

addb(mdl, 'simulink/Signal Routing/Mux', 'Mux_iref', [150 515 155 600]);
addb(mdl, 'simulink/Signal Routing/Mux', 'Mux_vdq',  [560 640 565 725]);
set_param([mdl '/Mux_iref'],'Inputs','2'); set_param([mdl '/Mux_vdq'],'Inputs','2');
addb(mdl, 'simulink/Signal Routing/Bus Creator', 'Telemetry', [1120 80 1125 700]);
set_param([mdl '/Telemetry'], 'Inputs','7');
addb(mdl, 'simulink/Sinks/Out1', 'i_dc',    [1220 43 1250 57]);
addb(mdl, 'simulink/Sinks/Out1', 'inv_tlm', [1220 383 1250 397]);
set_param([mdl '/inv_tlm'],'Port','2');

% power path
wire(mdl, 'v_dc/1',    'DCLink/1');
wire(mdl, 'DCLink/R1', 'Bridge/L1');
wire(mdl, 'DCLink/R2', 'Bridge/L2');
wire(mdl, 'SolverConfig/R1', 'Bridge/L1');
for k = 1:3
    wire(mdl, ['Bridge/R' num2str(k)],    ['LCLFilter/L' num2str(k)]);
    wire(mdl, ['LCLFilter/R' num2str(k)], ['GridSide/L' num2str(k)]);
end

% control path
wire(mdl, 'GridSide/1',   'GridAngle_ideal/1', 'v_abc');
wire(mdl, 'LCLFilter/1',  'CurrentLoop/1', 'i1_abc');      % inverter-side current
wire(mdl, 'GridSide/1',   'CurrentLoop/2');
wire(mdl, 'GridAngle_ideal/1', 'CurrentLoop/3', 'theta');
wire(mdl, 'Id_ref/1',     'CurrentLoop/4');
wire(mdl, 'Iq_ref/1',     'CurrentLoop/5');
wire(mdl, 'CurrentLoop/1','Modulator_SVPWM/1', 'Vd');
wire(mdl, 'CurrentLoop/2','Modulator_SVPWM/2', 'Vq');
wire(mdl, 'GridAngle_ideal/1', 'Modulator_SVPWM/3');
wire(mdl, 'Modulator_SVPWM/1', 'Bridge/1', 'gates');

wire(mdl, 'Id_ref/1','Mux_iref/1');   wire(mdl, 'Iq_ref/1','Mux_iref/2');
wire(mdl, 'CurrentLoop/1','Mux_vdq/1'); wire(mdl, 'CurrentLoop/2','Mux_vdq/2');

% telemetry
wire(mdl, 'CurrentLoop/3','Telemetry/1', 'i_dq');
wire(mdl, 'Mux_iref/1',   'Telemetry/2', 'i_dq_ref');
wire(mdl, 'Mux_vdq/1',    'Telemetry/3', 'v_dq_cmd');
wire(mdl, 'GridAngle_ideal/1','Telemetry/4');
wire(mdl, 'LCLFilter/1',  'Telemetry/5');
wire(mdl, 'LCLFilter/2',  'Telemetry/6', 'i2_abc');
wire(mdl, 'GridSide/1',   'Telemetry/7');
wire(mdl, 'DCLink/1',     'i_dc/1', 'i_dc');
wire(mdl, 'Telemetry/1',  'inv_tlm/1');

set_param(mdl, 'SolverType','Fixed-step', 'Solver','FixedStepDiscrete', ...
    'FixedStep','ip.Ts_power', 'StopTime','0.1', 'SimscapeLogType','none', ...
    'SaveOutput','on', 'SaveFormat','Dataset', ...
    'SignalLogging','on', 'SignalLoggingName','logsout');

note(mdl, [60 780], { ...
    'SWITCHED deliverable inverter: dq current loop -> SVPWM -> bridge -> LCL -> grid.'
    'THD is measured on i2_abc, the GRID-side current, in inv_grid_thd_check.'
    'Modulator_SVPWM is Belal''s block and GridAngle_ideal is Aqib''s PLL - both stubs.'
    'CurrentLoop, Modulator_SVPWM and LCLFilter are links to invLib.'});

save_system(mdl, fullfile(here, [mdl '.slx']));
fprintf('Built %s\n', fullfile(here, [mdl '.slx']));
end

% ========================================================================= util

function code = gridAngleCode()
code = sprintf('%s\n', ...
 'function theta = grid_angle(v_abc)', ...
 '%#codegen', ...
 '% Grid voltage angle straight off the Clarke transform. Not a PLL: no loop,', ...
 '% no filter, no dynamics - which is the point. Aqib''s SRF-PLL replaces it,', ...
 '% and its lag then shows up as a difference against this baseline.', ...
 'v_al = (2/3)*(v_abc(1) - 0.5*v_abc(2) - 0.5*v_abc(3));', ...
 'v_be = (2/3)*(sqrt(3)/2)*(v_abc(2) - v_abc(3));', ...
 'theta = atan2(v_be, v_al);');
end

function p = subsys(parent, name, pos)
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
add_block('built-in/PMIOPort', [parent '/' name]);
set_param([parent '/' name], 'Port', num2str(num), 'Side', side, 'Position', pos);
end

function wire(parent, from, to, name)
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
    if numel(grp) < idx
        if tok(1) == 'L', grp = ph.RConn; else, grp = ph.LConn; end
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
