function buildInvLib()
%BUILDINVLIB  Build models/inverter/invLib.slx - the shared inverter blocks.
%
% Blocks that more than one inverter model uses live here and are LINKED into
% the models, not copied, so the averaged and switched versions cannot drift
% apart. Same arrangement as models/wind/windLib.slx, and inv_model_lint.m
% checks the links are resolved. The library is locked: edit it here, re-run
% this script, and the models pick the change up.
%
% Contents:
%   CurrentLoop   dq-frame PI current control with cross-coupling decoupling
%                 and grid-voltage feedforward. Duc's block in the W4-W9 split.
%
% Owner: Duc Pham

lib  = 'invLib';
here = fileparts(mfilename('fullpath'));
addpath(here);

if bdIsLoaded(lib), close_system(lib, 0); end
new_system(lib, 'Library');
open_system(lib);
set_param(lib, 'Lock', 'off');

%% ==================================================================== CurrentLoop
% Interface - this is a seam with two other people, so it is fixed:
%   in   i_abc  (3)  measured inverter current, A
%   in   v_abc  (3)  measured PCC voltage, V   (feedforward)
%   in   theta  (1)  grid angle, rad           <- Aqib's SRF-PLL
%   in   Id_ref (1)  active current command, A <- Aqib's DC voltage loop
%   in   Iq_ref (1)  reactive current command, A
%   out  Vd     (1)  d-axis voltage command, V  -> Belal's SVPWM
%   out  Vq     (1)  q-axis voltage command, V  -> Belal's SVPWM
%   out  i_dq   (2)  measured [Id; Iq], for telemetry and tuning
%
% Vd/Vq are in VOLTS, not per-unit and not a modulation index. The modulator
% divides by V_dc, because only the modulator knows which modulation scheme is
% in use and therefore what the ceiling is. Belal needs theta as well; it comes
% from the PLL directly rather than through here.
cl = [lib '/CurrentLoop'];
add_block('built-in/Subsystem', cl, 'Position', [200 100 340 220]);
clearSubsystem(cl);

addb(cl, 'simulink/Sources/In1', 'i_abc',  [ 40  60  70  74]);
addb(cl, 'simulink/Sources/In1', 'v_abc',  [ 40 120  70 134]);
addb(cl, 'simulink/Sources/In1', 'theta',  [ 40 180  70 194]);
addb(cl, 'simulink/Sources/In1', 'Id_ref', [ 40 300  70 314]);
addb(cl, 'simulink/Sources/In1', 'Iq_ref', [ 40 420  70 434]);
for k = 1:5
    nm = {'i_abc','v_abc','theta','Id_ref','Iq_ref'};
    set_param([cl '/' nm{k}], 'Port', num2str(k));
end

% --- Park transform: abc -> dq, aligned so that d follows the grid vector
addb(cl, 'simulink/User-Defined Functions/MATLAB Function', 'Park', [150 55 300 200]);
chart = sfroot().find('-isa','Stateflow.EMChart','Path',[cl '/Park']);
chart.Script = parkCode();

addb(cl, 'simulink/Signal Routing/Demux', 'Demux_i', [340 60 345 140]);
addb(cl, 'simulink/Signal Routing/Demux', 'Demux_v', [340 160 345 240]);
set_param([cl '/Demux_i'], 'Outputs', '2');
set_param([cl '/Demux_v'], 'Outputs', '2');

wire(cl, 'i_abc/1', 'Park/1');
wire(cl, 'v_abc/1', 'Park/2');
wire(cl, 'theta/1', 'Park/3');
wire(cl, 'Park/1', 'Demux_i/1', 'i_dq');
wire(cl, 'Park/2', 'Demux_v/1', 'v_dq');

% --- error, PI, decoupling, feedforward
% d axis:  Vd = PI(Id_ref - Id) + Vgd - wL*Iq
% q axis:  Vq = PI(Iq_ref - Iq) + Vgq + wL*Id
axes = {'d', 'q'};
for k = 1:2
    a = axes{k};
    y = 300 + 220*(k-1);
    addb(cl, 'simulink/Math Operations/Sum', ['err_' a], [420 y 450 y+30]);
    set_param([cl '/err_' a], 'Inputs', '+-');
    addb(cl, 'simulink/Discrete/Discrete PID Controller', ['PI_' a], [500 y-15 570 y+45]);
    set_param([cl '/PI_' a], 'Controller','PI', 'Form','Parallel', ...
        'TimeDomain','Discrete-time', 'SampleTime','ip.Ts_ctrl', ...
        'IntegratorMethod','Backward Euler', ...
        'P','ip.Kp_i', 'I','ip.Ki_i', ...
        'LimitOutput','on', 'UpperSaturationLimit','ip.V_pi_max', ...
        'LowerSaturationLimit','-ip.V_pi_max', 'AntiWindupMode','clamping');
    addb(cl, 'simulink/Math Operations/Gain', ['decouple_' a], [500 y+90 560 y+130]);
    addb(cl, 'simulink/Math Operations/Sum', ['sum_' a], [640 y 670 y+30]);
    set_param([cl '/sum_' a], 'Inputs', '+++');
    % One-sample computation delay: what the command is sampled, computed and
    % applied through in a real digital controller. It is also what breaks the
    % algebraic loop - with an implicit Simscape local solver the plant output
    % depends on its input within the same step, so a direct-feedthrough
    % controller closes an unsolvable loop. Modelling the delay is the honest
    % fix, and the 500 Hz bandwidth already budgets for it.
    addb(cl, 'simulink/Discrete/Unit Delay', ['delay_' a], [700 y-5 740 y+35]);
    set_param([cl '/delay_' a], 'SampleTime', 'ip.Ts_ctrl');
    addb(cl, 'simulink/Sinks/Out1', ['V' a], [790 y+8 820 y+22]);
end
set_param([cl '/decouple_d'], 'Gain', '-ip.wL');   % -wL*Iq
set_param([cl '/decouple_q'], 'Gain', 'ip.wL');    % +wL*Id
set_param([cl '/Vd'], 'Port', '1');
set_param([cl '/Vq'], 'Port', '2');

wire(cl, 'Id_ref/1',   'err_d/1');
wire(cl, 'Demux_i/1',  'err_d/2');          % Id
wire(cl, 'Iq_ref/1',   'err_q/1');
wire(cl, 'Demux_i/2',  'err_q/2');          % Iq
wire(cl, 'err_d/1',    'PI_d/1');
wire(cl, 'err_q/1',    'PI_q/1');
wire(cl, 'Demux_i/2',  'decouple_d/1');     % d axis is coupled to Iq
wire(cl, 'Demux_i/1',  'decouple_q/1');     % q axis is coupled to Id
wire(cl, 'PI_d/1',        'sum_d/1');
wire(cl, 'Demux_v/1',     'sum_d/2');       % Vgd feedforward
wire(cl, 'decouple_d/1',  'sum_d/3');
wire(cl, 'PI_q/1',        'sum_q/1');
wire(cl, 'Demux_v/2',     'sum_q/2');       % Vgq feedforward
wire(cl, 'decouple_q/1',  'sum_q/3');
wire(cl, 'sum_d/1', 'delay_d/1');
wire(cl, 'sum_q/1', 'delay_q/1');
wire(cl, 'delay_d/1', 'Vd/1');
wire(cl, 'delay_q/1', 'Vq/1');

% i_dq is delayed by the same one sample as Vd/Vq. Two reasons: it is the
% measurement the controller actually acted on that step, and it leaves the
% block with NO direct feedthrough on any output at all - so CurrentLoop can be
% dropped into any model, including Aqib's and Belal's, without creating an
% algebraic loop through the plant.
addb(cl, 'simulink/Discrete/Unit Delay', 'delay_i', [660 55 700 95]);
set_param([cl '/delay_i'], 'SampleTime', 'ip.Ts_ctrl');
% flatten the 2x1 from the MATLAB Function to a plain 2-wide vector, so the
% telemetry logs as N-by-2 like every other signal
addb(cl, 'simulink/Math Operations/Reshape', 'i_dq_vector', [730 60 770 90]);
set_param([cl '/i_dq_vector'], 'OutputDimensionality', '1-D array');
addb(cl, 'simulink/Sinks/Out1', 'i_dq', [820 68 850 82]);
set_param([cl '/i_dq'], 'Port', '3');
wire(cl, 'Park/1', 'delay_i/1');
wire(cl, 'delay_i/1', 'i_dq_vector/1');
wire(cl, 'i_dq_vector/1', 'i_dq/1');

% Deliberately VIRTUAL, not atomic. An atomic subsystem is analysed as one
% block for direct feedthrough, and Simulink then reports feedthrough on every
% output if any single input-output path has it - which drags Vd and Vq into an
% algebraic loop with the plant even though both sit behind a unit delay.
% (MinAlgLoopOccurrences does not rescue it either; Simulink says so directly.)
% Virtual means the delays are seen where they actually are, and the loop
% resolves. The controller rate is carried by the PI blocks and the unit
% delays, which all run at ip.Ts_ctrl, so the command still updates once per
% control period - the rate is set by the blocks that matter, not by a
% subsystem-level declaration.
area(cl, 'Park transform   abc -> dq, d aligned with the grid voltage vector', [130 35 365 255], '[0.90 0.90 1.00]');
area(cl, 'd axis   active current   Vd = PI(Id_ref - Id) + Vgd - wL*Iq', [395 265 845 455], '[0.90 1.00 0.90]');
area(cl, 'q axis   reactive current   Vq = PI(Iq_ref - Iq) + Vgq + wL*Id', [395 485 845 675], '[0.90 1.00 0.90]');
area(cl, 'Measured current out (one control step old, like Vd/Vq)', [640 35 875 115], '[0.94 0.94 0.94]');

set_param(cl, 'TreatAsAtomicUnit', 'off');

%% ======================================================================= Bridge
% Six discrete IGBTs with antiparallel diodes, drawn as three legs with S1..S6
% gate tags - the textbook layout, so it reads the way the team expects rather
% than hiding in one block. Electrically identical to Converter (Three-Phase);
% inv_thd_check and inv_grid_thd_check are what prove that.
%
%   in   gates  (6)  [a+ a- b+ b- c+ c-]  - the Six-Pulse Gate Multiplexer order
%   out  v_pole (3)  each leg output referred to the DC NEGATIVE RAIL, not to
%                    ground: the DC bus floats in the grid-connected model
%   in/out  DCp DCn (left)   a b c (right)
%
% GATE NUMBERING. The S1..S6 tags use the classic firing-sequence convention
% from the textbooks - S1/S3/S5 are the upper devices of a/b/c, S4/S6/S2 the
% lower ones. That is NOT the order the modulator emits, which is by leg:
%
%       tag   device      gates(...)
%       S1    a upper         1
%       S4    a lower         2
%       S3    b upper         3
%       S6    b lower         4
%       S5    c upper         5
%       S2    c lower         6
%
% The uppers coincide (S1/S3/S5 <- 1/3/5) and the lowers do not. That is what
% makes this mapping dangerous to transcribe: a mistake looks right on the top
% row and silently swaps the lower devices between phases, which is
% shoot-through. Verified by firing one gate at a time into a split DC bus.
br = [lib '/Bridge'];
add_block('built-in/Subsystem', br, 'Position', [200 660 340 780]);
clearSubsystem(br);

port(br, 'DCp', 1, 'Left',  [40  60  50  80]);
port(br, 'DCn', 2, 'Left',  [40 600  50 620]);
port(br, 'a',   3, 'Right', [1180 250 1190 270]);
port(br, 'b',   4, 'Right', [1180 300 1190 320]);
port(br, 'c',   5, 'Right', [1180 350 1190 370]);

addb(br, 'simulink/Sources/In1',          'gates', [40 700 70 714]);
addb(br, 'simulink/Signal Routing/Demux', 'Demux', [120 540 125 860]);
set_param([br '/Demux'], 'Outputs', '6');
wire(br, 'gates/1', 'Demux/1');

% gates(k) -> the tag that drives it
tagOf  = {'S1','S4','S3','S6','S5','S2'};        % by gates index
for k = 1:6
    y = 540 + 55*(k-1);
    addb(br, 'simulink/Signal Routing/Goto', ['Goto_' tagOf{k}], [170 y 230 y+25]);
    set_param([br '/Goto_' tagOf{k}], 'GotoTag', tagOf{k}, 'TagVisibility', 'local');
    wire(br, sprintf('Demux/%d',k), ['Goto_' tagOf{k} '/1']);
end

% three legs: upper row S1 S3 S5, lower row S4 S6 S2
legTag = {'S1','S3','S5'; 'S4','S6','S2'};       % row 1 upper, row 2 lower
phn    = {'a','b','c'};
addb(br, 'simulink/Signal Routing/Mux', 'Mux_vpole', [1080 600 1085 700]);
set_param([br '/Mux_vpole'], 'Inputs', '3');
addb(br, 'simulink/Sinks/Out1', 'v_pole', [1150 643 1180 657]);

for k = 1:3
    x0 = 300 + 260*(k-1);
    for r = 1:2
        yb  = 100 + 260*(r-1);
        tag = legTag{r,k};
        addb(br, 'simulink/Signal Routing/From', ['From_' tag], [x0 yb x0+50 yb+25]);
        set_param([br '/From_' tag], 'GotoTag', tag);
        addb(br, 'nesl_utility/Simulink-PS Converter', ['gate_' tag], [x0 yb+45 x0+50 yb+85]);
        addb(br, 'ee_lib/Semiconductors & Converters/IGBT (Ideal, Switching)', tag, ...
             [x0+80 yb+35 x0+150 yb+105]);
        set_param([br '/' tag], ...
            'diode_param','ee.enum.semiconductors.protectionDiode.nodynamics', ...
            'Vth','ip.Vth_gate', 'Vf','ip.Vf_dev', 'Ron','ip.Ron_dev', 'Goff','ip.Goff_dev', ...
            'diode_Vf','ip.Vf_dev', 'diode_Ron','ip.Ron_dev', 'diode_Goff','ip.Goff_dev');
        wire(br, ['From_' tag '/1'],  ['gate_' tag '/1']);
        wire(br, ['gate_' tag '/R1'], [tag '/L1']);              % gate
    end
    up = legTag{1,k};  lo = legTag{2,k};
    wire(br, 'DCp/L1',    [up '/R1']);                           % DC+ -> upper C
    wire(br, [up '/R2'],  [lo '/R1']);                           % upper E -> lower C = pole
    wire(br, [lo '/R2'],  'DCn/L1');                             % lower E -> DC-
    wire(br, [up '/R2'],  [phn{k} '/L1']);                       % pole -> phase port

    % pole voltage sensed directly under its own leg, so the measurement chain
    % stays next to what it measures instead of crossing the diagram
    addb(br, 'ee_lib/Sensors & Transducers/Voltage Sensor', ['Vp_' phn{k}], ...
         [x0+80 560 x0+130 600]);
    addb(br, 'nesl_utility/PS-Simulink Converter', ['v_pole_' phn{k}], ...
         [x0+80 630 x0+130 670]);
    wire(br, ['Vp_' phn{k} '/L1'], [up '/R2']);
    wire(br, ['Vp_' phn{k} '/R2'], 'DCn/L1');
    wire(br, ['Vp_' phn{k} '/R1'], ['v_pole_' phn{k} '/L1']);
    wire(br, ['v_pole_' phn{k} '/1'], ['Mux_vpole/' num2str(k)]);
end
wire(br, 'Mux_vpole/1', 'v_pole/1');

% grouping boxes - what turns six switches and their plumbing into a diagram
area(br, 'Gate driver  -  gates(1..6) fanned out to the S1..S6 tags', ...
     [30 505 275 900], '[0.90 0.90 1.00]');
for k = 1:3
    x0 = 300 + 260*(k-1);
    area(br, sprintf('Leg %s   -  %s upper / %s lower', upper(phn{k}), ...
         legTag{1,k}, legTag{2,k}), [x0-25 75 x0+175 480], '[0.90 1.00 0.90]');
end
area(br, 'Pole voltage measurement  -  each leg referred to the DC NEGATIVE rail', ...
     [290 540 1200 690], '[0.94 0.94 0.94]');

%% ===================================================================== LCLFilter
% L1 - Cf/Rd - L2, wye capacitor bank with a FLOATING star point (three-wire:
% there is no zero-sequence path to give it, and grounding it would create one).
%
%   in/out  a b c (left)   inverter side
%   in/out  a b c (right)  grid side
%   out     i1_abc  inverter-side current - what the current loop controls
%   out     i2_abc  grid-side current     - what THD is measured on
%
% Every RLC field is bound to an ip.* value, including the ones the chosen
% structure does not use, so no Simscape default can survive a later change of
% structure. inv_model_lint checks it.
lf = [lib '/LCLFilter'];
add_block('built-in/Subsystem', lf, 'Position', [200 300 340 420]);
clearSubsystem(lf);

port(lf, 'a_inv', 1, 'Left',  [30  60  40  80]);
port(lf, 'b_inv', 2, 'Left',  [30 160  40 180]);
port(lf, 'c_inv', 3, 'Left',  [30 260  40 280]);
port(lf, 'a_grid',4, 'Right', [1180  60 1190  80]);
port(lf, 'b_grid',5, 'Right', [1180 160 1190 180]);
port(lf, 'c_grid',6, 'Right', [1180 260 1190 280]);

addb(lf, 'ee_lib/Passive/RLC Assemblies/RLC (Three-Phase)', 'L1_branch', [300 40 380 300]);
set_param([lf '/L1_branch'], 'port_option','ee.enum.threePhasePort.expanded', ...
    'component_structure','ee.enum.rlc.structure.SeriesRL', ...
    'R','ip.R1', 'L','ip.L1', 'C','ip.Cf');
addb(lf, 'ee_lib/Passive/RLC Assemblies/RLC (Three-Phase)', 'Cf_branch', [560 420 640 660]);
set_param([lf '/Cf_branch'], 'port_option','ee.enum.threePhasePort.expanded', ...
    'component_structure','ee.enum.rlc.structure.SeriesRC', ...
    'R','ip.Rd', 'L','ip.L1', 'C','ip.Cf');
addb(lf, 'ee_lib/Passive/RLC Assemblies/RLC (Three-Phase)', 'L2_branch', [760 40 840 300]);
set_param([lf '/L2_branch'], 'port_option','ee.enum.threePhasePort.expanded', ...
    'component_structure','ee.enum.rlc.structure.SeriesRL', ...
    'R','ip.R2', 'L','ip.L2', 'C','ip.Cf');

addb(lf, 'simulink/Signal Routing/Mux', 'Mux_i1', [1000 700 1005 840]);
addb(lf, 'simulink/Signal Routing/Mux', 'Mux_i2', [1000 880 1005 1020]);
set_param([lf '/Mux_i1'], 'Inputs','3');
set_param([lf '/Mux_i2'], 'Inputs','3');
addb(lf, 'simulink/Sinks/Out1', 'i1_abc', [1080 763 1110 777]);
addb(lf, 'simulink/Sinks/Out1', 'i2_abc', [1080 943 1110 957]);
set_param([lf '/i2_abc'], 'Port','2');

phn = {'a','b','c'};
for k = 1:3
    y = 40 + 100*(k-1);
    addb(lf, 'ee_lib/Sensors & Transducers/Current Sensor', ['I1_' phn{k}], [140 y 190 y+40]);
    addb(lf, 'ee_lib/Sensors & Transducers/Current Sensor', ['I2_' phn{k}], [940 y 990 y+40]);
    addb(lf, 'nesl_utility/PS-Simulink Converter', ['i1_' phn{k}], [860 700+70*(k-1) 910 740+70*(k-1)]);
    addb(lf, 'nesl_utility/PS-Simulink Converter', ['i2_' phn{k}], [860 880+70*(k-1) 910 920+70*(k-1)]);

    wire(lf, [phn{k} '_inv/L1'],   ['I1_' phn{k} '/L1']);
    wire(lf, ['I1_' phn{k} '/R2'], ['L1_branch/L' num2str(k)]);
    wire(lf, ['L1_branch/R' num2str(k)], ['Cf_branch/L' num2str(k)]);   % midpoint
    wire(lf, ['L1_branch/R' num2str(k)], ['L2_branch/L' num2str(k)]);
    wire(lf, ['L2_branch/R' num2str(k)], ['I2_' phn{k} '/L1']);
    wire(lf, ['I2_' phn{k} '/R2'], [phn{k} '_grid/L1']);

    wire(lf, ['I1_' phn{k} '/R1'], ['i1_' phn{k} '/L1']);
    wire(lf, ['i1_' phn{k} '/1'], ['Mux_i1/' num2str(k)]);
    wire(lf, ['I2_' phn{k} '/R1'], ['i2_' phn{k} '/L1']);
    wire(lf, ['i2_' phn{k} '/1'], ['Mux_i2/' num2str(k)]);
end
wire(lf, 'Cf_branch/R1', 'Cf_branch/R2');      % floating capacitor star point
wire(lf, 'Cf_branch/R2', 'Cf_branch/R3');
wire(lf, 'Mux_i1/1', 'i1_abc/1');
wire(lf, 'Mux_i2/1', 'i2_abc/1');

area(lf, 'L1   inverter side   sized for the ripple current', [275 15 405 325], '[0.90 1.00 0.90]');
area(lf, 'Cf + Rd   damped shunt, FLOATING star point', [530 395 665 685], '[0.90 0.90 1.00]');
area(lf, 'L2   grid side   what the capacitor works against', [735 15 865 325], '[0.90 1.00 0.90]');
area(lf, 'Current measurement   i1 is controlled, i2 is what the grid sees (THD)', [110 690 1130 1045], '[0.94 0.94 0.94]');

%% ============================================================== Modulator_SVPWM
% STUB - Belal owns the real modulator. This exists so the LCL can be verified
% end to end, and it is a correct SVPWM rather than a placeholder: min-max
% zero-sequence injection is mathematically identical to classical
% sector-and-timing SVPWM and reaches the same V_dc/sqrt(3) ceiling.
%
%   in   Vd, Vq  V    from CurrentLoop
%   in   theta   rad  from the PLL
%   out  gates   6    [a+ a- b+ b- c+ c-], the Six-Pulse Gate Multiplexer order
md = [lib '/Modulator_SVPWM'];
add_block('built-in/Subsystem', md, 'Position', [200 480 340 600]);
clearSubsystem(md);

addb(md, 'simulink/Sources/In1', 'Vd',    [30  60  60  74]);
addb(md, 'simulink/Sources/In1', 'Vq',    [30 120  60 134]);
addb(md, 'simulink/Sources/In1', 'theta', [30 180  60 194]);
set_param([md '/Vq'],'Port','2'); set_param([md '/theta'],'Port','3');
addb(md, 'simulink/Sources/Digital Clock', 'Clock',  [30 240  90 280]);
addb(md, 'simulink/Sources/Constant',      'f_sw',   [30 310  90 340]);
addb(md, 'simulink/Sources/Constant',      'Vdc',    [30 370  90 400]);
addb(md, 'simulink/Sources/Constant',      'N_dead', [30 430  90 460]);
set_param([md '/Clock'],  'SampleTime','ip.Ts_power');
set_param([md '/f_sw'],   'Value','ip.f_sw');
set_param([md '/Vdc'],    'Value','ip.V_dc');
set_param([md '/N_dead'], 'Value','ip.N_dead');

addb(md, 'simulink/User-Defined Functions/MATLAB Function', 'svpwm', [170 55 340 465]);
chart = sfroot().find('-isa','Stateflow.EMChart','Path',[md '/svpwm']);
chart.Script = svpwmCode();
addb(md, 'simulink/Math Operations/Reshape', 'gates_vector', [400 240 450 280]);
set_param([md '/gates_vector'], 'OutputDimensionality','1-D array');
addb(md, 'simulink/Sinks/Out1', 'gates', [510 253 540 267]);

wire(md, 'Vd/1','svpwm/1'); wire(md, 'Vq/1','svpwm/2'); wire(md, 'theta/1','svpwm/3');
wire(md, 'Clock/1','svpwm/4'); wire(md, 'f_sw/1','svpwm/5');
wire(md, 'Vdc/1','svpwm/6');  wire(md, 'N_dead/1','svpwm/7');
wire(md, 'svpwm/1','gates_vector/1');
wire(md, 'gates_vector/1','gates/1');

note(lib, [40 700], { ...
    'Shared inverter blocks. LINK these into models - do not copy.'
    'The library is locked; edit buildInvLib.m and re-run it.'
    'CurrentLoop returns Vd, Vq in VOLTS. The modulator divides by V_dc.'
    'Modulator_SVPWM is a STUB so the LCL can be tested - Belal owns the real one.'});

set_param(lib, 'Lock', 'on');
save_system(lib, fullfile(here, [lib '.slx']));
fprintf('Built %s\n', fullfile(here, [lib '.slx']));
end

% ========================================================================= util

function code = parkCode()
code = sprintf('%s\n', ...
 'function [i_dq, v_dq] = park(i_abc, v_abc, theta)', ...
 '%#codegen', ...
 '% Amplitude-invariant Park transform, d aligned with the grid voltage vector.', ...
 '%', ...
 '% With theta the grid angle from the PLL, a balanced grid gives v_dq = [Vpk; 0],', ...
 '% so Id is the active current and Iq the reactive current. Amplitude-invariant', ...
 '% (the 2/3 scaling) means Id is a real amperes peak, not a scaled quantity -', ...
 '% the current limit and the rating are then the same number everywhere.', ...
 'c = [cos(theta), cos(theta - 2*pi/3), cos(theta + 2*pi/3)];', ...
 's = [sin(theta), sin(theta - 2*pi/3), sin(theta + 2*pi/3)];', ...
 'i_dq = (2/3)*[ c*i_abc(:); -s*i_abc(:) ];', ...
 'v_dq = (2/3)*[ c*v_abc(:); -s*v_abc(:) ];');
end

function clearSubsystem(p)
inner = find_system(p, 'SearchDepth', 1, 'Type', 'Block');
for k = 1:numel(inner)
    if ~strcmp(inner{k}, p), delete_block(inner{k}); end
end
end

function addb(parent, src, name, pos)
add_block(src, [parent '/' name]);
set_param([parent '/' name], 'Position', pos);
end

function code = svpwmCode()
code = sprintf('%s\n', ...
 'function g6 = svpwm(Vd, Vq, theta, t, f_sw, Vdc, Ndead)', ...
 '%#codegen', ...
 '% SVPWM by min-max zero-sequence injection, with dead time.', ...
 '%', ...
 '% STUB - Belal owns the real modulator. This is a correct SVPWM rather than a', ...
 '% placeholder: min-max injection is mathematically identical to classical', ...
 '% sector-and-timing SVPWM and reaches the same V_dc/sqrt(3) ceiling.', ...
 'persistent gprev cnt', ...
 'if isempty(gprev)', ...
 '    gprev = zeros(3,1);', ...
 '    cnt   = Ndead*ones(3,1);        % start with the blanking already expired', ...
 'end', ...
 '', ...
 'v = [ Vd*cos(theta)         - Vq*sin(theta); ...', ...
 '      Vd*cos(theta-2*pi/3)  - Vq*sin(theta-2*pi/3); ...', ...
 '      Vd*cos(theta+2*pi/3)  - Vq*sin(theta+2*pi/3) ];', ...
 '', ...
 '% Zero-sequence injection. Common to all three phases, so it cancels in every', ...
 '% line-to-line voltage and drives no current in a three-wire system - it only', ...
 '% buys headroom, and that headroom IS the 15.5%% SVPWM has over SPWM.', ...
 'v = v - (max(v) + min(v))/2;', ...
 '', ...
 'm = v/(Vdc/2);                      % per-leg modulation index', ...
 'm = min(max(m, -1), 1);             % clip; overmodulation is not modelled', ...
 '', ...
 'frac = t*f_sw - floor(t*f_sw);      % triangular carrier, -1 .. 1', ...
 'tri  = 4*abs(frac - 0.5) - 1;', ...
 'g    = double(m > tri);             % raw leg command, 1 = upper on', ...
 '', ...
 '% Dead time: on any leg transition blank BOTH devices for Ndead steps.', ...
 'g6 = zeros(6,1);', ...
 'for k = 1:3', ...
 '    if g(k) ~= gprev(k)', ...
 '        cnt(k) = 0;', ...
 '    elseif cnt(k) < Ndead', ...
 '        cnt(k) = cnt(k) + 1;', ...
 '    end', ...
 '    live = cnt(k) >= Ndead;', ...
 '    g6(2*k-1) = double(g(k) == 1 && live);      % upper', ...
 '    g6(2*k)   = double(g(k) == 0 && live);      % lower', ...
 'end', ...
 'gprev = g;');
end

function port(parent, name, num, side, pos)
%PORT  Physical (Simscape) connection port on a subsystem boundary.
add_block('built-in/PMIOPort', [parent '/' name]);
set_param([parent '/' name], 'Port', num2str(num), 'Side', side, 'Position', pos);
end

function area(parent, label, pos, colour)
%AREA  Labelled grouping box. Purely cosmetic, but it is what turns a wall of
%      blocks into something a teammate can read at a glance.
persistent n
if isempty(n), n = 0; end
n = n + 1;
nm = sprintf('%s/__area%d', parent, n);
add_block('built-in/Area', nm, 'Position', pos);
as = find_system(bdroot(parent), 'FindAll','on', 'Type','annotation');
for k = 1:numel(as)
    if strcmp(get_param(as(k),'Name'), sprintf('__area%d', n))
        set_param(as(k), 'Name', label, 'BackgroundColor', colour);
        break
    end
end
end

function wire(parent, from, to, name)
%WIRE  "Block/port" to "Block/port". A port written "L3"/"R2" is a physical
%      connection port; a bare number is a signal port.
h = add_line(parent, portOf(parent, from, 'out'), portOf(parent, to, 'in'), 'autorouting','on');
if nargin > 3, set_param(h, 'Name', name); end
end

function h = portOf(parent, spec, dir)
parts = split(string(spec), '/');
ph  = get_param([parent '/' char(parts(1))], 'PortHandles');
tok = char(parts(2));
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
