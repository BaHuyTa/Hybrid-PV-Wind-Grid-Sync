function r = testPLLStandin(srcModel, blk)
%TESTPLLSTANDIN  The PLL stand-in on its own, against the success criterion
%   "PLL re-lock after 30 deg phase jump < 100 ms"   (README)
%
%   r = testPLLStandin()              the reference build
%   r = testPLLStandin("myModel")     yours
%   r = testPLLStandin("intSystem_aqibPLL", "Inverter/SRF_PLL")   Aqib's block
%
% The integrated runs can't test this: the ee_lib grid source has a fixed phase.
% So this copies the PLL_standin block out of intSystem into a tiny model and
% drives it with an ideal three-phase voltage whose angle does three things:
%   t = 0      starts 90 deg away from the PLL's initial guess  (lock-in)
%   t = 0.2 s  jumps +30 deg                                    (the criterion)
%   t = 0.5 s  frequency steps 50 -> 50.5 Hz                    (tracking)
% "Locked" = error inside +/-1 deg and staying there.
%

arguments
    srcModel (1,1) string = "intSystem"      % whose PLL_standin to test
    blk      (1,1) string = "Inverter/PLL_standin"
end
if srcModel == "intSystem_aqibPLL" && nargin < 2, blk = "Inverter/SRF_PLL"; end
P  = intPaths();
xp = intParams();
if ~bdIsLoaded(srcModel), load_system(fullfile(P.here, srcModel + ".slx")); end

mdl = 'pllTest';
if bdIsLoaded(mdl), close_system(mdl, 0); end
new_system(mdl);
mw = get_param(mdl, 'ModelWorkspace'); mw.DataSource = 'MATLAB Code';
mw.MATLABCode = sprintf('xp = intParams();\nip = invParams();'); mw.reload();
set_param(mdl, 'SolverType','Fixed-step', 'Solver','FixedStepDiscrete', ...
    'FixedStep','1e-5', 'StopTime','0.8', 'SignalLogging','on', ...
    'ReturnWorkspaceOutputs','on');

% The "grid": theta_true(t), then va = Vm cos(theta), the same convention as
% the ee_lib source (va = Vm sin(wt) = Vm cos(wt - pi/2)).
t  = (0:1e-5:0.8)';
w0 = 2*pi*50;
th = w0*t - pi/2 + 0 ...                      % base
   + deg2rad(30)*(t >= 0.2) ...               % phase jump
   + 2*pi*0.5*(t - 0.5).*(t >= 0.5);          % +0.5 Hz
vabc = xp.pll.Vm*[cos(th), cos(th - 2*pi/3), cos(th + 2*pi/3)];
add_block('simulink/Sources/From Workspace', [mdl '/grid'], 'VariableName','vgrid', ...
    'SampleTime','1e-5', 'Position', [40 50 110 80]);
add_block(srcModel + "/" + blk, [mdl '/PLL'], 'Position', [180 40 300 90]);
add_block('simulink/Sinks/Terminator', [mdl '/T'], 'Position', [360 55 380 75]);
add_line(mdl, 'grid/1', 'PLL/1');
h = add_line(mdl, 'PLL/1', 'T/1');
set_param(h, 'Name', 'theta_hat');
ph = get_param([mdl '/PLL'], 'PortHandles');
set_param(ph.Outport(1), 'DataLogging','on');

% Lock-in test: PLL starts at 0 rad, the grid at -90 deg.
in = Simulink.SimulationInput(mdl);
in = in.setVariable('vgrid', timeseries(vabc, t));
xp0 = xp; xp0.pll.theta0 = 0;
in = in.setVariable('xp', xp0, 'Workspace', mdl);
out = sim(in);

y  = out.logsout.get('theta_hat').Values;
tk = y.Time;
% The stand-in's output carries one control-period delay by design (a copy of
% GridAngle_ideal's), so compare it with the true angle one period earlier.
% Aqib's SRF_PLL has no such delay: compare it with the true angle now.
dly = xp.Ts_ctrl * ~contains(blk, "SRF_PLL");
tt = interp1(t, th, max(tk - dly, 0));
e  = rad2deg(mod(y.Data(:) - tt + pi, 2*pi) - pi);

r.lockin_ms = lockTime(tk, e, 0,   0.2) * 1e3;
r.jump_ms   = lockTime(tk, e, 0.2, 0.5) * 1e3;
r.jump_peak_deg = max(abs(e(tk >= 0.2 & tk < 0.5)));
seg = tk > 0.7;
r.freq_step_err_deg = max(abs(e(seg)));          % steady error while at 50.5 Hz
r.pass_jump = r.jump_ms < 100;
r.t = tk; r.e = e;

fprintf(['%s / %s:\n' ...
    '  lock-in from 90 deg     : %.1f ms\n' ...
    '  30 deg jump re-lock     : %.1f ms   (criterion < 100 ms)  %s\n' ...
    '  +0.5 Hz step, settled   : %.3f deg error\n'], ...
    srcModel, blk, r.lockin_ms, r.jump_ms, passStr(r.pass_jump), r.freq_step_err_deg);
end

function T = lockTime(t, e, t0, t1)
seg = t >= t0 & t < t1;
ts  = t(seg);  bad = abs(e(seg)) > 1;
if ~any(bad), T = 0; elseif bad(end), T = Inf; else, T = ts(find(bad,1,'last')+1) - t0; end
end

function s = passStr(p)
if p, s = 'PASS'; else, s = 'FAIL'; end
end
