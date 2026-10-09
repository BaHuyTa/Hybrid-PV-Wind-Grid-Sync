function T = checkBuild(mdl, opts)
%CHECKBUILD  Grade a hand-built integration model against the reference build.
%
%   T = checkBuild("intSystem")                  structure + nominal + PLL test + trip
%   T = checkBuild("intSystem", Simulate=false)  structure only (seconds, not minutes)
%   T = checkBuild("intSystem", Island=true)     also the island run (+~150 s)
%
% Run from the folder that holds the model (models/integration in the repo).
% Prints one PASS/FAIL line per check and returns them as a table. Part 1 reads
% the model; part 2 runs "nominal" (~3 min), testPLLStandin and "trip" (~2.5 min)
% and compares the numbers with the reference build's, written into this file.
%

arguments
    mdl (1,1) string = "intSystem"
    opts.Simulate (1,1) logical = true
    opts.Island   (1,1) logical = false
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
% The PLL is either the stand-in (Inverter/PLL_standin) or Aqib's library block
% (Inverter/SRF_PLL, decided 2 Oct). Each gets its own checks below.
pllName = "PLL_standin";
if ~exists([m '/Inverter/PLL_standin']) && exists([m '/Inverter/SRF_PLL']), pllName = "SRF_PLL"; end
need = ["PV","Wind","Inverter","DCBus","DCLinkLoop_standin","Meters", ...
        "Inverter/" + pllName,"Inverter/GridAngle_ideal","PV/I_pv"];
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
if pllName == "PLL_standin"
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
else
% Aqib's SRF_PLL: a resolved library link at the controller rate (its gains live in the library).
p = [m '/Inverter/SRF_PLL'];
add('SRF_PLL: library link intact', strcmp(get_param(p,'LinkStatus'),'resolved'), get_param(p,'LinkStatus'));
add('SRF_PLL: Ts = xp.Ts_ctrl', abs(ev(get_param(p,'Ts')) - xp.Ts_ctrl) < 1e-12, tryGet(p,'Ts'));
end

% -- the PLL really drives the loop, and the owners' library links are intact -----
ph = get_param([m '/Inverter/' char(pllName)], 'PortHandles');
dst = get_param(get_param(ph.Outport(1),'Line'), 'DstBlockHandle');
dn  = string(get_param(dst, 'Name'));
add('PLL output feeds CurrentLoop + Modulator', all(ismember(["CurrentLoop","Modulator_SVPWM"], dn)), strjoin(dn, ', '));
for b = ["CurrentLoop","Modulator_SVPWM","LCLFilter"]
    s = get_param([m '/Inverter/' char(b)], 'LinkStatus');
    add("Library link intact: " + b, strcmp(s,'resolved'), s);
end

% -- trip path (Protection_PCC_LabManual Part B) -------------------------------
fprintf('\n== %s: trip path ==\n', m);
tc = [m '/trip_cmd'];
add('trip_cmd is a Step: xp.trip.t, 0 -> 1', exists(tc) && strcmp(get_param(tc,'BlockType'),'Step') ...
    && ev(get_param(tc,'Time')) == xp.trip.t && ev(get_param(tc,'InitialValue')) == 0 ...
    && ev(get_param(tc,'FinalValue')) == 1, tryGet(tc,'Time'));
add('Block exists: TripGate', exists([m '/TripGate']), '');
add('Inverter Id_ref comes from TripGate out 1', isSrc([m '/Inverter'], 2, 'TripGate', 1), srcName([m '/Inverter'], 2));
add('Inverter Iq_ref comes from TripGate out 2', isSrc([m '/Inverter'], 3, 'TripGate', 2), srcName([m '/Inverter'], 3));
% In 1: the DC loop directly, or through the SFS rotation. In 3: trip_cmd directly, or
% max(trip_cmd, relay) once Redhwan's relay is in (5 Oct).
tripFromOr = isSrc([m '/TripGate'], 3, 'trip_or', 1) && isSrc([m '/trip_or'], 1, 'trip_cmd', 1);
add('TripGate takes the DC loop, Iq_ref, the trip', (isSrc([m '/TripGate'], 1, 'DCLinkLoop_standin', 1) ...
    || isSrc([m '/TripGate'], 1, 'SFS', 1)) && (isSrc([m '/TripGate'], 3, 'trip_cmd', 1) || tripFromOr), '');
add('PV has inport 3 "enable"', exists([m '/PV/enable']) && strcmp(get_param([m '/PV/enable'],'Port'),'3'), '');
mc = find_system([m '/PV'], 'SearchDepth',1, 'Name','MPPT Controller');
add('MPPT Controller gates its PWM with enable', ~isempty(mc) && exists([mc{1} '/enable']) ...
    && ~isempty(find_system(mc{1}, 'SearchDepth',1, 'BlockType','Product')), '');
add('PV enable comes from TripGate run', isSrc([m '/PV'], 3, 'TripGate', 3), srcName([m '/PV'], 3));
% Wind's enable is found by NAME: it is port 3 in the sandbox, port 2 in Henry's build.
we = find_system([m '/Wind'], 'SearchDepth',1, 'BlockType','Inport', 'Name','enable');
okW = false;  infoW = 'no inport "enable" in Wind';
if ~isempty(we)
    pw = str2double(get_param(we{1},'Port'));  hw = srcBlk([m '/Wind'], pw);
    okW = hw > 0 && strcmp(get_param(hw,'BlockType'),'Product') && ~isSrc([m '/Wind'], pw, 'wind_enable', 1);
    infoW = sprintf('enable is port %d, fed by %s', pw, srcName([m '/Wind'], pw));
end
add('Wind enable = wind_enable x run (not the constant)', okW, infoW);

% -- PCC: loads and breakers ------------------------------------------------------
fprintf('\n== %s: PCC ==\n', m);
gs = [m '/Inverter/GridSide/'];
for b = ["Brk_grid","Brk_site","Brk_rlc"]
    add("Breaker exists: " + b, exists([gs char(b)]) && contains(get_param([gs char(b)],'ReferenceBlock'), 'Circuit Breaker'), '');
end
sl = [gs 'SiteLoad'];
okS = exists(sl) && contains(get_param(sl,'ReferenceBlock'), 'Constant Power Load') ...
      && abs(ev(get_param(sl,'active_power'))*unitScale(get_param(sl,'active_power_unit')) - xp.pcc.site.P) < 1 ...
      && ev(get_param(sl,'FRated')) == 50;
add('SiteLoad: constant PQ, 250 kW at 50 Hz', okS, tryGet(sl,'active_power') + " " + tryGet(sl,'active_power_unit'));
rl = [gs 'RLC_test'];
okR = exists(rl) && contains(get_param(rl,'ReferenceBlock'), 'Wye-Connected Load') ...
      && contains(get_param(rl,'component_structure_PQ'), 'ParallelRLC') ...
      && abs(ev(get_param(rl,'P')) - xp.pcc.rlc.P) < 1 && abs(ev(get_param(rl,'Qpos')) - xp.pcc.rlc.QL) < 1 ...
      && abs(ev(get_param(rl,'Qneg')) + xp.pcc.rlc.QC) < 1 && ev(get_param(rl,'Vmag0')) == 400;
add('RLC_test: parallel RLC, matched, Qf 1, starts in AC steady state', okR, '');
for b = ["grid","site","rlc"]
    st = [gs char(b) '_open'];
    ok = exists(st) && ev(get_param(st,'InitialValue')) == xp.pcc.(b).open0 ...
         && ev(get_param(st,'FinalValue')) == 1 - xp.pcc.(b).open0 && ev(get_param(st,'Time')) == xp.pcc.(b).t;
    add("Breaker command " + b + "_open uses xp.pcc." + b, ok, '');
end
add('SiteLoad reactive power unit is var (A*V), like xp.pcc.site.Q', exists(sl) ...
    && strcmp(get_param(sl,'reactive_power_unit'),'A*V'), tryGet(sl,'reactive_power_unit'));

% -- anti-islanding + gate enable (Protection_PCC_LabManual Part G, done 5 Oct) -----
% Only on the SRF_PLL build: the stand-in reference intSystem does not carry them.
if pllName == "SRF_PLL"
fprintf('\n== %s: anti-islanding (SFS + relay) and gate enable ==\n', m);
sf = [m '/SFS'];
add('SFS rotates the DC-loop and Iq refs into TripGate', exists(sf) && isSrc(sf, 1, 'DCLinkLoop_standin', 1) ...
    && isSrc(sf, 2, 'Iq_ref', 1) && isSrc([m '/TripGate'], 1, 'SFS', 1) && isSrc([m '/TripGate'], 2, 'SFS', 2), '');
add('SFS takes f_hz from the Inverter (out 4)', exists(sf) && isSrc(sf, 3, 'Inverter', 4), srcName(sf, 3));
okG = exists([sf '/kSFS']) && ev(get_param([sf '/kSFS'],'Gain')) == xp.sfs.kSFS ...
      && exists([sf '/to_theta']) && abs(ev(get_param([sf '/to_theta'],'Gain')) - xp.sfs.sign*pi/2) < 1e-12 ...
      && exists([sf '/cf0']) && ev(get_param([sf '/cf0'],'Value')) == xp.sfs.cf0;
add('SFS: cf0, kSFS, theta = sign*pi/2*cf from xp.sfs', okG, '');
okS2 = exists([sf '/df_smooth']) && contains(get_param([sf '/df_smooth'],'Denominator'), 'xp.sfs.tau_f') ...
       && exists([sf '/sfs_on']) && ev(get_param([sf '/sfs_on'],'Time')) == xp.prot.t_arm;
add('SFS: smoothed f error (tau_f), switched on at t_arm', okS2, '');
add('Inverter f_hz goes through a one-step delay (no algebraic loop)', isSrc([m '/Inverter/f_hz'], 1, 'f_hz_delay', 1), ...
    srcName([m '/Inverter/f_hz'], 1));
rb = [m '/AntiIslandingRelay'];
okRel = exists(rb) && strcmp(get_param(rb,'LinkStatus'),'resolved') ...
        && strcmp(get_param(rb,'ReferenceBlock'),'protectionLib/AntiIslandingRelay') ...
        && ev(get_param(rb,'t_arm')) == xp.prot.t_arm && ev(get_param(rb,'t_pickup')) == xp.prot.t_pickup ...
        && isSrc(rb, 1, 'Inverter', 4);
add('Relay: linked protectionLib, t_arm/t_pickup from xp.prot, fed f_hz', okRel, tryGet(rb,'t_arm'));
add('trip = max(trip_cmd, relay) into TripGate in 3', tripFromOr && isSrc([m '/trip_or'], 2, 'relay_to_double', 1), '');
add('Inverter enable (in 4) from TripGate run', isSrc([m '/Inverter'], 4, 'TripGate', 3), srcName([m '/Inverter'], 4));
add('Bridge gates go through gate_block (gates x enable)', isSrc([m '/Inverter/Bridge'], 1, 'gate_block', 1) ...
    && isSrc([m '/Inverter/gate_block'], 1, 'Modulator_SVPWM', 1), srcName([m '/Inverter/Bridge'], 1));
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
        % Reference numbers are the stand-in build's. With Aqib's SRF_PLL only the specs apply.
        if pllName == "PLL_standin"
        cmp('P_ac',    0.01*ref.P_ac, 'kW', 1e-3);
        cmp('P_pv',    0.01*ref.P_pv, 'kW', 1e-3);
        cmp('P_wind',  0.01*ref.P_wind, 'kW', 1e-3);
        cmp('dev_pct', 0.3,  '%',  1);
        cmp('recover', 0.010,'s',  1);
        cmp('THDtot',  0.3,  '%',  1);
        cmp('PF',      0.002,'',   1);
        end
        add('Spec: bus deviation < 5 %', r.pass_dev, sprintf('%.2f %%', r.dev_pct));
        add('Spec: bus back in +/-1 % < 200 ms', r.pass_recover, sprintf('%.0f ms', 1e3*max(r.recover)));
        add('Spec: grid current THD < 5 %', r.pass_thd, sprintf('%.2f %%', r.THDtot));
        add('No nuisance trip in a normal run', ~r.nuisance_trip, sprintf('t_trip = %g s', r.t_trip));
        if pllName == "PLL_standin"
        add('PLL starts locked (f_hat within 50 +/- 0.5 Hz)', r.f_min > 49.5 && r.f_max < 50.5, ...
            sprintf('%.2f-%.2f Hz (ref 50.00-50.00)', r.f_min, r.f_max));
        end
    end
    if pllName == "PLL_standin"           % Aqib's SRF_PLL carries its own re-lock test
    fprintf('\n== %s: PLL stand-in on its own ==\n', m);
    rp = testPLLStandin(mdl);
    add('Spec: PLL re-lock after 30 deg < 100 ms', rp.pass_jump, sprintf('%.1f ms (ref 36.8)', rp.jump_ms));
    end

    % Reference (4 Oct 2026): inverter 2.0 ms, PV 0.9 ms, wind 0.5 ms, bus 2.19 %.
    fprintf('\n== %s: trip at 0.5 s (~150 s) ==\n', m);
    rt = runIntegration("trip", Model=mdl, Save=false);
    if isempty(rt)
        add('trip scenario runs', false, 'simulation failed - see warning above');
    else
        p = rt.prot;
        add('Trip: inverter current < 5 % within 5 ms', p.i_inv_off_ms < 5, sprintf('%.1f ms (ref 2.0)', p.i_inv_off_ms));
        add('Trip: PV current < 1 A within 5 ms', p.i_pv_off_ms < 5, sprintf('%.1f ms (ref 0.9)', p.i_pv_off_ms));
        add('Trip: wind current < 1 A within 5 ms', p.i_wind_off_ms < 5, sprintf('%.1f ms (ref 0.5)', p.i_wind_off_ms));
        add('Trip: bus stays inside +/-5 %', p.dev_after_pct < 5, sprintf('%.2f %% (ref 2.19)', p.dev_after_pct));
    end
    if opts.Island
        % Reference: islanded 99.4-100.9 %, 49.15-50.00 Hz, PCC dead 32 ms after the trip.
        fprintf('\n== %s: island at 0.5 s, trip at 0.6 s (~150 s) ==\n', m);
        % With SFS in the model, "island" is run with SFS OFF: it shows what passive
        % protection alone sees. island_sfs below is the same island with SFS ON.
        noSFS = {};  if pllName == "SRF_PLL", noSFS = {"sfs.cf0", 0, "sfs.kSFS", 0}; end
        ri = runIntegration("island", Model=mdl, Save=false, Set=noSFS);
        if isempty(ri)
            add('island scenario runs', false, 'simulation failed - see warning above');
        else
            p = ri.prot;
            add('Island holds V and f (passive protection blind)', all(p.Vpcc_island_pct > 90 & p.Vpcc_island_pct < 110) ...
                && all(p.f_island > 47 & p.f_island < 52), sprintf('%.0f-%.0f %%, %.2f-%.2f Hz', p.Vpcc_island_pct, p.f_island));
            add('Island: PCC < 5 % within 100 ms of the trip', p.Vpcc_off_ms < 100, sprintf('%.0f ms (ref 32)', p.Vpcc_off_ms));
        end
        if pllName == "SRF_PLL"
            % Reference (5 Oct, test copy): relay trips 65.6 ms after the island, PCC dead 30.7 ms later.
            fprintf('\n== %s: island at 0.5 s, SFS + relay on their own (~200 s) ==\n', m);
            rs = runIntegration("island_sfs", Model=mdl, Save=false);
            if isempty(rs)
                add('island_sfs scenario runs', false, 'simulation failed - see warning above');
            else
                p = rs.prot;
                add('Spec SC5: relay trips the island by itself < 2 s', rs.t_trip < 2.5 && p.detect_ms < 2000, ...
                    sprintf('%.1f ms (ref 65.6)', p.detect_ms));
                add('island_sfs: PCC < 5 % within 100 ms of the trip', p.pass && p.Vpcc_off_ms < 100, sprintf('%.0f ms (ref 31)', p.Vpcc_off_ms));
            end
        end
    end
end

T = cell2table(rows, 'VariableNames', {'check','pass','detail'});
fprintf('\n%d/%d checks pass.\n', nnz(T.pass), height(T));
end

function tf = exists(p), tf = getSimulinkBlockHandle(p) > 0; end
function h = srcBlk(blk, port)
% Block driving input port "port" of blk (-1 if unconnected).
h = -1;
if ~exists(blk), return, end
ph = get_param(blk, 'PortHandles');
if numel(ph.Inport) < port, return, end
ln = get_param(ph.Inport(port), 'Line');
if ln > 0, h = get_param(ln, 'SrcBlockHandle'); end
end
function s = srcName(blk, port)
h = srcBlk(blk, port);  s = '';
if h > 0, s = get_param(h, 'Name'); end
end
function tf = isSrc(blk, port, name, outPort)
% True if input "port" of blk is driven by output "outPort" of the block called name.
tf = false;  h = srcBlk(blk, port);
if h <= 0 || ~strcmp(get_param(h,'Name'), name), return, end
ph = get_param(blk, 'PortHandles');
sp = get_param(get_param(ph.Inport(port), 'Line'), 'SrcPortHandle');
tf = get_param(sp, 'PortNumber') == outPort;
end
function k = unitScale(u)
switch u, case 'kW', k = 1e3; case 'MW', k = 1e6; otherwise, k = 1; end
end
function s = tern(c, a, b), if c, s = a; else, s = b; end, end
function tf = hasVar(mw, v), try, evalin(mw, [v ';']); tf = true; catch, tf = false; end, end
function s = tryGet(b, prm)
if iscell(b), if isempty(b), s = ''; return, end, b = b{1}; end
try, s = get_param(b, prm); catch, s = ''; end
end
