function R = linearizeStandins()
%LINEARIZESTANDINS  Stability margins of the two stand-in loops (DC link, PLL).
%
%   R = linearizeStandins()
%
% Method (simulink-linearize skill): slLinearizer + getLoopTransfer, opening
% each loop at its controller output, at a simulation snapshot in steady state.
%
% The integrated model can't be linearized as it is: its switched bridge and
% PV boost are hard discontinuities, and they linearize to zero. So each loop is
% linearized around the most faithful LINEARIZABLE plant:
%
%   DC loop  - the real DCLinkLoop_standin and DCBus blocks (copied from
%              intSystem) around Duc's AVERAGED inverter (invPlantAvg: the real
%              CurrentLoop, the LCL and the grid, with no switching). The DC side
%              closes by power balance, i_inv = 1.5*(v_dq . i_dq) / v_dc. The
%              sources are a constant-power 118.2 kW (the nominal operating
%              point), whose negative incremental resistance is included.
%   PLL      - the real PLL_standin (copied from intSystem) on an ideal 50 Hz
%              grid, i.e. the stiff-grid case.
%

intPaths();
xp = intParams();
if ~bdIsLoaded('intSystem'), load_system('intSystem'); end
load_system('invPlantAvg');

%% ---- DC-link loop -------------------------------------------------------------
m = 'linDC';
if bdIsLoaded(m), close_system(m, 0); end
new_system(m);
mw = get_param(m, 'ModelWorkspace'); mw.DataSource = 'MATLAB Code';
mw.MATLABCode = sprintf('ip = invParams();\nxp = intParams();'); mw.reload();
set_param(m, 'SolverType','Fixed-step', 'Solver','ode3', 'FixedStep','xp.Ts', 'StopTime','0.4');

add_block('built-in/Subsystem', [m '/Inv'], 'Position', [400 100 520 200]);
Simulink.BlockDiagram.copyContentsToSubsystem('invPlantAvg', [m '/Inv']);
add_block('intSystem/DCBus', [m '/DCBus'], 'Position', [700 100 800 200]);
add_block('intSystem/DCLinkLoop_standin', [m '/DCLoop'], 'Position', [200 100 300 160]);
add_block('simulink/Sources/Constant', [m '/Iq_ref'], 'Value','0', 'Position', [300 180 330 200]);
% inverter DC current by power balance
add_block('simulink/Signal Routing/Bus Selector', [m '/sel'], 'OutputSignals','v_dq_cmd,i_dq', ...
    'Position', [560 150 565 190]);
add_block('simulink/Math Operations/Dot Product', [m '/p'], 'Position', [590 150 620 180]);
add_block('simulink/Math Operations/Gain', [m '/x1p5'], 'Gain','1.5', 'Position', [630 150 660 180]);
add_block('simulink/Math Operations/Divide', [m '/i_inv'], 'Position', [670 150 690 190]);
% sources: constant power, i = P / v
add_block('simulink/Sources/Constant', [m '/P_src'], 'Value','118.2e3', 'Position', [560 60 620 80]);
add_block('simulink/Math Operations/Divide', [m '/i_src'], 'Position', [650 60 670 100]);
add_block('simulink/Sources/Constant', [m '/zero'], 'Value','0', 'Position', [650 115 670 130]);
add_block('simulink/Sinks/Terminator', [m '/T1'], 'Position', [560 110 580 130]);
l = @(a,b) add_line(m, a, b, 'autorouting','smart');
l('DCLoop/1','Inv/1'); l('Iq_ref/1','Inv/2'); l('Inv/1','T1/1');
l('Inv/2','sel/1'); l('sel/1','p/1'); l('sel/2','p/2'); l('p/1','x1p5/1'); l('x1p5/1','i_inv/1');
l('DCBus/1','i_inv/2'); l('P_src/1','i_src/1'); l('DCBus/1','i_src/2');
l('i_src/1','DCBus/1'); l('zero/1','DCBus/2'); l('i_inv/1','DCBus/3'); l('DCBus/1','DCLoop/1');

s = slLinearizer(m);
addPoint(s, [m '/DCLoop'], 1);                      % Id_ref: the loop is opened here
s.OperatingPoints = 0.4;                            % snapshot in steady state
s.Options = linearizeOptions('SampleTime', xp.Ts_ctrl);
Ldc = getLoopTransfer(s, [m '/DCLoop/1'], -1);      % negative-feedback convention
R.dc = marginsOf(Ldc);
R.dc.L = Ldc;

%% ---- PLL ------------------------------------------------------------------------
m = 'linPLL';
if bdIsLoaded(m), close_system(m, 0); end
new_system(m);
mw = get_param(m, 'ModelWorkspace'); mw.DataSource = 'MATLAB Code';
mw.MATLABCode = 'xp = intParams();'; mw.reload();
set_param(m, 'SolverType','Fixed-step', 'Solver','ode3', 'FixedStep','1e-5', 'StopTime','0.1');
ph = [0 -2*pi/3 2*pi/3];
for k = 1:3          % ee_lib convention: va = Vm*sin(wt)
    add_block('simulink/Sources/Sine Wave', sprintf('%s/v%d', m, k), 'Amplitude','xp.pll.Vm', ...
        'Frequency','2*pi*50', 'Phase', num2str(ph(k), 17), 'Position', [40 40+50*k 70 70+50*k]);
end
add_block('simulink/Signal Routing/Mux', [m '/mux'], 'Inputs','3', 'Position', [110 90 115 230]);
add_block('intSystem/Inverter/PLL_standin', [m '/PLL'], 'Position', [160 130 260 190]);
add_block('simulink/Sinks/Terminator', [m '/T'], 'Position', [300 150 320 170]);
for k = 1:3, add_line(m, sprintf('v%d/1', k), sprintf('mux/%d', k)); end
add_line(m, 'mux/1', 'PLL/1'); add_line(m, 'PLL/1', 'T/1');

s = slLinearizer(m);
addPoint(s, [m '/PLL/w_hat'], 1);                   % loop opened at the frequency estimate
s.OperatingPoints = 0.1;
s.Options = linearizeOptions('SampleTime', xp.Ts_ctrl);
Lpll = getLoopTransfer(s, [m '/PLL/w_hat/1'], -1);
R.pll = marginsOf(Lpll);
R.pll.L = Lpll;

fprintf(['\nDC-link loop stand-in (at 118 kW, averaged inverter):\n' ...
         '  crossover %.1f Hz | phase margin %.1f deg | gain margin %.1f dB | stable %d\n' ...
         'PLL stand-in (stiff grid):\n' ...
         '  crossover %.1f Hz | phase margin %.1f deg | gain margin %.1f dB | stable %d\n'], ...
    R.dc.fc, R.dc.PM, R.dc.GMdB, R.dc.stable, R.pll.fc, R.pll.PM, R.pll.GMdB, R.pll.stable);
end

function r = marginsOf(L)
S = allmargin(L);
r.PM   = min(S.PhaseMargin);
r.fc   = S.PMFrequency(find(S.PhaseMargin == r.PM, 1)) / (2*pi);
r.GMdB = 20*log10(min(S.GainMargin));
r.fg   = S.GMFrequency(find(S.GainMargin == min(S.GainMargin), 1)) / (2*pi);
r.stable = S.Stable;
end
