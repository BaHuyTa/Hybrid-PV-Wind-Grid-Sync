function T = checkBuild(mdl, opts)
%CHECKBUILD  Grade a hand-built integration model against the reference build.
%
%   T = checkBuild("intSystem")                  structure + nominal run + PLL test
%   T = checkBuild("intSystem", Simulate=false)  structure only (seconds, not minutes)
%
% Run from the folder that holds the model (models/integration in the repo).
% Prints one PASS/FAIL line per check and returns them as a table. Part 1 reads
% the model; part 2 runs "nominal" (~100 s) and testPLLStandin and compares the
% numbers with the reference build's, which are written into this file below.
%

arguments
    mdl (1,1) string = "intSystem"
    opts.Simulate (1,1) logical = true
end

P = intPaths();
m = char(mdl);
if ~bdIsLoaded(m), load_system(fullfile(P.here, m + ".slx")); end
mw = get_param(m, 'ModelWorkspace');
ev = @(expr) evalin(mw, expr);                 % evaluate in the model's workspace
xp = intParams();
rows = {};
    function add(name, ok, detail)
        rows(end+1, :) = {string(name), ok, string(detail)};
        fprintf('  %-4s  %-46s %s\n', tern(ok,'PASS','FAIL'), name, detail);
    end

fprintf('\n== %s: structure ==\n', m);

% -- solver and workspace -------------------------------------------------------
add('Fixed-step solver at 0.5 us', ...
    strcmp(get_param(m,'SolverType'),'Fixed-step') && abs(ev(get_param(m,'FixedStep')) - 5e-7) < 1e-12, ...
    sprintf('%s, step %s', get_param(m,'Solver'), get_param(m,'FixedStep')));
hasVars = all(cellfun(@(v) hasVar(mw, v), {'ip','wp','xp'}));
add('Model workspace defines ip, wp, xp', hasVars, '');
add('Simscape logging off', strcmp(get_param(m,'SimscapeLogType'),'none'), get_param(m,'SimscapeLogType'));

% -- the blocks the scripts look for, by name ------------------------------------
need = ["PV","Wind","Inverter","DCBus","DCLinkLoop_standin","Meters", ...
        "Inverter/PLL_standin","Inverter/GridAngle_ideal","PV/I_pv"];
for b = need
    add("Block exists: " + b, exists([m '/' char(b)]), '');
end

% -- PV patches ------------------------------------------------------------------
add('PV: inport G is port 2', exists([m '/PV/G']) && strcmp(get_param([m '/PV/G'],'Port'),'2'), '');
add('PV: outport i_dc', exists([m '/PV/i_dc']), '');
c = [m '/PV/Boost Converter/Cout'];
add('PV: Cout pre-charged to 700 V', exists(c) && strcmp(get_param(c,'vc_specify'),'on') ...
    && abs(ev(get_param(c,'vc')) - 700) < 1e-9, tryGet(c,'vc'));
sc = find_system([m '/PV'], 'SearchDepth',1, 'ReferenceBlock','nesl_utility/Solver Configuration');
add('PV: Solver Configuration uses local solver', ~isempty(sc) && strcmp(get_param(sc{1},'UseLocalSolver'),'on'), '');

% -- the bus -------------------------------------------------------------------
ig = find_system([m '/DCBus'], 'BlockType','Integrator');
add('DCBus: one integrator, IC = 700 V', numel(ig) == 1 && abs(ev(get_param(ig{1},'InitialCondition')) - 700) < 1e-9, '');
gn = find_system([m '/DCBus'], 'BlockType','Gain');
add('DCBus: gain = 1/C = 22.73', numel(gn) == 1 && abs(ev(get_param(gn{1},'Gain')) - 1/xp.C_bus) < 1e-6, tryGet(gn,'Gain'));
sm = find_system([m '/DCBus'], 'BlockType','Sum');
add('DCBus: sum signs ++- (pv, wind, inv)', numel(sm) == 1 && contains(strrep(get_param(sm{1},'Inputs'),'|',''), '++-'), tryGet(sm,'Inputs'));

% -- stand-ins ----------------------------------------------------------------------
pid = find_system([m '/DCLinkLoop_standin'], 'MaskType','PID 1dof');   % any PID block, whatever it's named
okPI = ~isempty(pid) && abs(ev(get_param(pid{1},'P')) - xp.dc.Kp) < 1e-6 ...
       && abs(ev(get_param(pid{1},'I')) - xp.dc.Ki) < 1e-6;
add('DC loop PI gains = xp.dc.Kp / Ki', okPI, sprintf('want %.2f / %.1f', xp.dc.Kp, xp.dc.Ki));
okLim = ~isempty(pid) && strcmp(get_param(pid{1},'LimitOutput'),'on') ...
       && abs(ev(get_param(pid{1},'UpperSaturationLimit')) - xp.dc.Id_max) < 1e-6 ...
       && strcmp(get_param(pid{1},'AntiWindupMode'),'clamping');
add('DC loop clamp +/-306.2 A, anti-windup', okLim, '');
pp = find_system([m '/Inverter/PLL_standin'], 'MaskType','PID 1dof');
okPLL = ~isempty(pp) && abs(ev(get_param(pp{1},'P')) - xp.pll.Kp) < 1e-6 ...
        && abs(ev(get_param(pp{1},'I')) - xp.pll.Ki) < 1e-3;
add('PLL PI gains = xp.pll.Kp / Ki', okPLL, sprintf('want %.1f / %.0f', xp.pll.Kp, xp.pll.Ki));
% Rates and start angle: -1 (inherited) runs ZOH/sample_theta at 0.5 us, which removes
% the one-sample delay; IC 0 instead of theta0 starts the PLL 90 deg out (30 Sep, Henry).
for b = ["ZOH","theta_int","sample_theta"]
    p = [m '/Inverter/PLL_standin/' char(b)];
    ok = exists(p) && abs(ev(get_param(p,'SampleTime')) - xp.Ts_ctrl) < 1e-12;
    add("PLL " + b + ": sample time xp.Ts_ctrl", ok, tryGet(p,'SampleTime'));
end
for b = ["theta_int","sample_theta"]
    p = [m '/Inverter/PLL_standin/' char(b)];
    ok = exists(p) && abs(ev(get_param(p,'InitialCondition')) - xp.pll.theta0) < 1e-9;
    add("PLL " + b + ": IC xp.pll.theta0", ok, tryGet(p,'InitialCondition'));
end

% -- the PLL really drives the loop, and the owners' library links are intact -----
ph = get_param([m '/Inverter/PLL_standin'], 'PortHandles');
dst = get_param(get_param(ph.Outport(1),'Line'), 'DstBlockHandle');
dn  = string(get_param(dst, 'Name'));
add('PLL output feeds CurrentLoop + Modulator', all(ismember(["CurrentLoop","Modulator_SVPWM"], dn)), strjoin(dn, ', '));
for b = ["CurrentLoop","Modulator_SVPWM","LCLFilter"]
    s = get_param([m '/Inverter/' char(b)], 'LinkStatus');
    add("Library link intact: " + b, strcmp(s,'resolved'), s);
end

if opts.Simulate
    fprintf('\n== %s: behaviour (nominal, ~100 s) ==\n', m);
    % Reference = Henry's DC-loop design (2 Oct 2026, xp.dc.Kp 18.714 / Ki 1773.9).
    % Old harness gains (12.57 / 251.5) gave dev 2.139 %, recover 0.0602 s, THD 1.607 %.
    ref = struct('P_ac',117.04e3, 'P_pv',98.55e3, 'P_wind',19.56e3, 'dev_pct',1.213, ...
                 'recover',0.0123, 'THDtot',1.615, 'PF',0.9988);
    r = runIntegration("nominal", Model=mdl, Save=false);
    if isempty(r)
        add('nominal scenario runs', false, 'simulation failed - see warning above');
    else
        add('Power balance closes (P_pv+P_wind = P_invdc)', abs(r.P_bal) < 200, sprintf('%.0f W', r.P_bal));
        cmp = @(f, tol, unit, scale) add(sprintf('%s matches reference', f), ...
            abs(r.(f) - ref.(f)) <= tol, sprintf('%.4g vs %.4g %s', r.(f)*scale, ref.(f)*scale, unit));
        cmp('P_ac',    0.01*ref.P_ac, 'kW', 1e-3);
        cmp('P_pv',    0.01*ref.P_pv, 'kW', 1e-3);
        cmp('P_wind',  0.01*ref.P_wind, 'kW', 1e-3);
        cmp('dev_pct', 0.3,  '%',  1);
        cmp('recover', 0.010,'s',  1);
        cmp('THDtot',  0.3,  '%',  1);
        cmp('PF',      0.002,'',   1);
        add('Spec: bus deviation < 5 %', r.pass_dev, sprintf('%.2f %%', r.dev_pct));
        add('Spec: bus back in +/-1 % < 200 ms', r.pass_recover, sprintf('%.0f ms', 1e3*max(r.recover)));
        add('Spec: grid current THD < 5 %', r.pass_thd, sprintf('%.2f %%', r.THDtot));
        add('PLL starts locked (f_hat within 50 +/- 0.5 Hz)', r.f_min > 49.5 && r.f_max < 50.5, ...
            sprintf('%.2f-%.2f Hz (ref 50.00-50.00)', r.f_min, r.f_max));
    end
    fprintf('\n== %s: PLL stand-in on its own ==\n', m);
    rp = testPLLStandin(mdl);
    add('Spec: PLL re-lock after 30 deg < 100 ms', rp.pass_jump, sprintf('%.1f ms (ref 36.8)', rp.jump_ms));
end

T = cell2table(rows, 'VariableNames', {'check','pass','detail'});
fprintf('\n%d/%d checks pass.\n', nnz(T.pass), height(T));
end

function tf = exists(p), tf = getSimulinkBlockHandle(p) > 0; end
function s = tern(c, a, b), if c, s = a; else, s = b; end, end
function tf = hasVar(mw, v), try, evalin(mw, [v ';']); tf = true; catch, tf = false; end, end
function s = tryGet(b, prm)
if iscell(b), if isempty(b), s = ''; return, end, b = b{1}; end
try, s = get_param(b, prm); catch, s = ''; end
end
