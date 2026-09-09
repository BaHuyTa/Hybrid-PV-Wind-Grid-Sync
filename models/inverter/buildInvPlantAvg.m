function buildInvPlantAvg()
%BUILDINVPLANTAVG  Build models/inverter/invPlantAvg.slx - the tuning model.
%
% Averaged inverter: the bridge and modulator are replaced by ideal controlled
% voltage sources that produce the commanded fundamental directly. Valid well
% below f_sw, which is exactly the band the current loop works in. This is the
% "averaged for controller tuning" half of the two-fidelity convention; the
% switched model (invPlantSw) stays for THD and final validation.
%
% What is REAL here:   the dq current loop (linked from invLib), the filter
%                      inductance, the grid.
% What is a STUB here: the modulator (Belal's SVPWM) and the grid angle
%                      (Aqib's SRF-PLL). Both are marked _ideal, both have no
%                      dynamics, and that is deliberate - the inner loop has to
%                      be tuned against a plant that is not also being disturbed
%                      by two loops that do not exist yet. Bandwidth separation
%                      says this is legitimate: the PLL is far slower.
%
% Interface:
%       in   Id_ref   A   active current command   <- Aqib's DC voltage loop
%       in   Iq_ref   A   reactive current command
%       out  i_dq     A   measured [Id; Iq]
%       out  inv_tlm  -   telemetry bus
%
% Owner: Duc Pham

mdl  = 'invPlantAvg';
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

%% ================================================================== ACSide
% Averaged bridge -> filter -> grid. The inverter is three controlled sources
% commanded with the phase voltages the modulator asks for.
%
% Both star points are grounded, so each phase is an independent R-L between a
% commanded voltage and the grid. That is the plant the PI is designed against.
% It does not represent zero-sequence behaviour, which a three-wire bridge
% cannot produce anyway.
s = subsys(mdl, 'ACSide', [620 80 760 220]);
addb(s, 'simulink/Sources/In1', 'v_abc_cmd', [30 60 60 74]);
addb(s, 'nesl_utility/Simulink-PS Converter', 'S2PS', [110 50 160 90]);
addb(s, 'ee_lib/Sources/Controlled Voltage Source (Three-Phase)', 'VSI_avg', [230 40 300 120]);
addb(s, 'ee_lib/Connectors & References/Phase Splitter', 'Split_inv', [360 40 400 120]);
% The real LCL, linked from invLib - the same block the switched model uses, so
% the two fidelities cannot disagree about the filter. Its resonance is in the
% plant here, which is the point: the current loop has to be shown not to
% excite it.
add_block([lib '/LCLFilter'], [s '/LCLFilter'], 'Position', [600 40 720 220]);
addb(s, 'ee_lib/Connectors & References/Phase Splitter', 'Split_pcc', [800 40 840 120]);
addb(s, 'ee_lib/Sources/Voltage Source (Three-Phase)', 'Grid', [920 40 990 120]);
% impedance_option is set EXPLICITLY - the block ships with a 1 MVA
% short-circuit level, which is a weak grid at this rating and destabilises the
% current loop through the PCC voltage feedforward. See invParams.
set_param([s '/Grid'], 'vline_rms','ip.V_ll', 'freq','ip.f_grid', 'shift','0', ...
    'impedance_option','ip.grid_Z_opt', 'SShortCircuit','ip.S_sc', 'XR','ip.grid_XR');
addb(s, 'ee_lib/Connectors & References/Electrical Reference', 'Gnd_inv',  [230 200 270 230]);
addb(s, 'ee_lib/Connectors & References/Electrical Reference', 'Gnd_grid', [920 200 960 230]);
% The whole physical network lives in this subsystem, so its Solver
% Configuration does too - unlike invPlantSw, where the DC rails cross the root.
addb(s, 'nesl_utility/Solver Configuration', 'SolverConfig', [1040 190 1110 230]);
set_param([s '/SolverConfig'], 'UseLocalSolver','on', ...
    'LocalSolverChoice','NE_BACKWARD_EULER_ADVANCER', 'LocalSolverSampleTime','ip.Ts_power');

wire(s, 'v_abc_cmd/1', 'S2PS/1');
wire(s, 'S2PS/R1',   'VSI_avg/L1');            % PS 3-vector command
wire(s, 'Gnd_inv/L1','VSI_avg/L2');            % inverter star point
wire(s, 'VSI_avg/R1','Split_inv/L1');          % composite -> a,b,c
wire(s, 'Split_pcc/L1','Grid/R1');             % a,b,c -> composite
wire(s, 'Gnd_grid/L1','Grid/L1');              % grid star point
wire(s, 'SolverConfig/R1','Grid/L1');

addb(s, 'simulink/Signal Routing/Mux', 'Mux_v', [1080 520 1085 660]);
set_param([s '/Mux_v'], 'Inputs','3');
addb(s, 'simulink/Sinks/Out1', 'i_abc',  [1160 363 1190 377]);   % inverter side
addb(s, 'simulink/Sinks/Out1', 'v_abc',  [1160 583 1190 597]);
addb(s, 'simulink/Sinks/Out1', 'i2_abc', [1160 443 1190 457]);   % grid side
set_param([s '/v_abc'],  'Port','2');
set_param([s '/i2_abc'], 'Port','3');
addb(s, 'ee_lib/Connectors & References/Electrical Reference', 'Gnd_meas', [900 700 940 730]);

ph = {'a','b','c'};
for k = 1:3
    wire(s, ['Split_inv/R' num2str(k)], ['LCLFilter/L' num2str(k)]);
    wire(s, ['LCLFilter/R' num2str(k)], ['Split_pcc/R' num2str(k)]);
    addb(s, 'ee_lib/Sensors & Transducers/Voltage Sensor', ['V_' ph{k}], [820 520+70*(k-1) 870 560+70*(k-1)]);
    addb(s, 'nesl_utility/PS-Simulink Converter', ['PS2S_v' ph{k}], [960 520+70*(k-1) 1010 560+70*(k-1)]);
    wire(s, ['V_' ph{k} '/L1'], ['LCLFilter/R' num2str(k)]);
    wire(s, ['V_' ph{k} '/R2'], 'Gnd_meas/L1');
    wire(s, ['V_' ph{k} '/R1'], ['PS2S_v' ph{k} '/L1']);
    wire(s, ['PS2S_v' ph{k} '/1'], ['Mux_v/' num2str(k)]);
end
wire(s, 'LCLFilter/1', 'i_abc/1');       % i1, what the loop controls
wire(s, 'LCLFilter/2', 'i2_abc/1');      % i2, what the grid sees
wire(s, 'Mux_v/1', 'v_abc/1');

%% ======================================================= stubs (not mine)
% Stand-in for Belal's SVPWM. Produces the commanded fundamental directly, with
% no carrier and no V_dc division, so there is nothing here to tune - it only
% has to be transparent. Replacing it with SVPWM + the switched bridge is the
% integration step.
s = subsys(mdl, 'Modulator_ideal', [400 80 540 180]);
addb(s, 'simulink/Sources/In1', 'Vd',    [30  60  60  74]);
addb(s, 'simulink/Sources/In1', 'Vq',    [30 120  60 134]);
addb(s, 'simulink/Sources/In1', 'theta', [30 180  60 194]);
set_param([s '/Vq'],'Port','2'); set_param([s '/theta'],'Port','3');
addb(s, 'simulink/User-Defined Functions/MATLAB Function', 'dq_to_abc', [150 55 300 200]);
chart = sfroot().find('-isa','Stateflow.EMChart','Path',[s '/dq_to_abc']);
chart.Script = invParkCode();
addb(s, 'simulink/Sinks/Out1', 'v_abc_cmd', [370 120 400 134]);
wire(s, 'Vd/1','dq_to_abc/1'); wire(s, 'Vq/1','dq_to_abc/2'); wire(s, 'theta/1','dq_to_abc/3');
wire(s, 'dq_to_abc/1','v_abc_cmd/1');

% Stand-in for Aqib's SRF-PLL. Computes the grid angle directly from the
% measured voltage - no loop, no filter, therefore no dynamics. Deliberate: the
% inner loop must be tuned against a plant that is not also moving because a
% PLL is settling. When the real PLL lands, its lag shows up as a difference
% against this baseline, which is the useful thing to measure.
s = subsys(mdl, 'GridAngle_ideal', [400 300 540 380]);
addb(s, 'simulink/Sources/In1', 'v_abc', [30 100 60 114]);
addb(s, 'simulink/User-Defined Functions/MATLAB Function', 'grid_angle', [150 60 300 160]);
chart = sfroot().find('-isa','Stateflow.EMChart','Path',[s '/grid_angle']);
chart.Script = gridAngleCode();
% The angle is a SAMPLED quantity: the PLL runs on the same processor at the
% same rate as the current loop, so its output is one control step old wherever
% it is used. Aqib's SRF-PLL will be discrete for the same reason. It also
% breaks the second algebraic loop - the one that runs grid angle -> modulator
% -> plant without passing through the current loop's own delay.
addb(s, 'simulink/Discrete/Unit Delay', 'sample_theta', [330 90 370 130]);
set_param([s '/sample_theta'], 'SampleTime', 'ip.Ts_ctrl');
addb(s, 'simulink/Sinks/Out1', 'theta', [420 103 450 117]);
wire(s, 'v_abc/1','grid_angle/1');
wire(s, 'grid_angle/1','sample_theta/1');
wire(s, 'sample_theta/1','theta/1');

%% ==================================================================== root
addb(mdl, 'simulink/Sources/In1', 'Id_ref', [60 300 90 314]);
addb(mdl, 'simulink/Sources/In1', 'Iq_ref', [60 360 90 374]);
set_param([mdl '/Iq_ref'], 'Port','2');

% CurrentLoop is a LINK to invLib - never a copy (inv_model_lint checks this).
add_block([lib '/CurrentLoop'], [mdl '/CurrentLoop'], 'Position', [200 100 340 260]);

addb(mdl, 'simulink/Signal Routing/Mux', 'Mux_iref', [150 295 155 380]);
addb(mdl, 'simulink/Signal Routing/Mux', 'Mux_vdq',  [560 430 565 515]);
set_param([mdl '/Mux_iref'], 'Inputs','2');
set_param([mdl '/Mux_vdq'],  'Inputs','2');
addb(mdl, 'simulink/Signal Routing/Bus Creator', 'Telemetry', [900 100 905 620]);
set_param([mdl '/Telemetry'], 'Inputs','6');
addb(mdl, 'simulink/Sinks/Out1', 'i_dq',    [1000 60 1030 74]);
addb(mdl, 'simulink/Sinks/Out1', 'inv_tlm', [1000 350 1030 364]);
set_param([mdl '/inv_tlm'], 'Port','2');

wire(mdl, 'ACSide/1',      'CurrentLoop/1', 'i_abc');
wire(mdl, 'ACSide/2',      'CurrentLoop/2', 'v_abc');
wire(mdl, 'GridAngle_ideal/1','CurrentLoop/3', 'theta');
wire(mdl, 'Id_ref/1',      'CurrentLoop/4');
wire(mdl, 'Iq_ref/1',      'CurrentLoop/5');
wire(mdl, 'CurrentLoop/1', 'Modulator_ideal/1', 'Vd');
wire(mdl, 'CurrentLoop/2', 'Modulator_ideal/2', 'Vq');
wire(mdl, 'GridAngle_ideal/1','Modulator_ideal/3');
wire(mdl, 'Modulator_ideal/1','ACSide/1', 'v_abc_cmd');
wire(mdl, 'ACSide/2',      'GridAngle_ideal/1');

wire(mdl, 'Id_ref/1', 'Mux_iref/1');
wire(mdl, 'Iq_ref/1', 'Mux_iref/2');
wire(mdl, 'CurrentLoop/1', 'Mux_vdq/1');
wire(mdl, 'CurrentLoop/2', 'Mux_vdq/2');

wire(mdl, 'CurrentLoop/3', 'Telemetry/1', 'i_dq');
wire(mdl, 'Mux_iref/1',    'Telemetry/2', 'i_dq_ref');
wire(mdl, 'Mux_vdq/1',     'Telemetry/3', 'v_dq_cmd');
wire(mdl, 'GridAngle_ideal/1', 'Telemetry/4', 'theta');
wire(mdl, 'ACSide/1',      'Telemetry/5', 'i_abc_m');
wire(mdl, 'ACSide/2',      'Telemetry/6', 'v_abc_m');
wire(mdl, 'CurrentLoop/3', 'i_dq/1');
wire(mdl, 'Telemetry/1',   'inv_tlm/1');

set_param(mdl, 'SolverType','Fixed-step', 'Solver','FixedStepDiscrete', ...
    'FixedStep','ip.Ts_power', 'StopTime','0.1', 'SimscapeLogType','none', ...
    'SaveOutput','on', 'SaveFormat','Dataset', ...
    'SignalLogging','on', 'SignalLoggingName','logsout');

note(mdl, [60 660], { ...
    'AVERAGED model - for tuning the current loop, not for THD. No switching.'
    'Modulator_ideal and GridAngle_ideal are stubs for Belal''s SVPWM and'
    'Aqib''s SRF-PLL. Both are dynamics-free on purpose, so the inner loop is'
    'tuned against a plant that is not also settling.'
    'CurrentLoop is a link to invLib - edit it there, not here.'});

save_system(mdl, fullfile(here, [mdl '.slx']));
fprintf('Built %s\n', fullfile(here, [mdl '.slx']));
end

% ========================================================================= util

function code = invParkCode()
code = sprintf('%s\n', ...
 'function v_abc = dq_to_abc(Vd, Vq, theta)', ...
 '%#codegen', ...
 '% Inverse of the amplitude-invariant Park transform in invLib/CurrentLoop.', ...
 '% Stand-in for the modulator: the commanded phase voltages appear directly,', ...
 '% with no carrier and no V_dc scaling.', ...
 'v_abc = [ Vd*cos(theta)           - Vq*sin(theta); ...', ...
 '          Vd*cos(theta - 2*pi/3)  - Vq*sin(theta - 2*pi/3); ...', ...
 '          Vd*cos(theta + 2*pi/3)  - Vq*sin(theta + 2*pi/3) ];');
end

function code = gridAngleCode()
code = sprintf('%s\n', ...
 'function theta = grid_angle(v_abc)', ...
 '%#codegen', ...
 '% Grid voltage angle straight off the Clarke transform. Not a PLL: no loop,', ...
 '% no filter, no dynamics - which is the point. It gives the inner loop an', ...
 '% exact angle so the loop can be tuned in isolation, and it gives Aqib''s', ...
 '% SRF-PLL a baseline to be measured against.', ...
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
