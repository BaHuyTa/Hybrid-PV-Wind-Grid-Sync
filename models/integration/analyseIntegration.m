function r = analyseIntegration(logsout, s)
%ANALYSEINTEGRATION  Turn one intSystem run into numbers, and check them.
%
%   r = analyseIntegration(logsout, scenario)
%
% Steady-state numbers are averaged over s.window. The bus and inverter
% currents are CHOPPED by the switching (a boost diode or a bridge conducts
% only part of each 100 us period), so a single sample means nothing, and even
% a window mean of 5 us samples is biased (the samples are synchronous with the
% carrier). Every power figure therefore comes from the model's energy meters
% (E = integral of v*i at the full 0.5 us step): P = dE/dt over the window.
%
% Checks against the README success criteria:
%   grid current THD < 5 %                  (read at the window)
%   DC bus deviation < 5 % of 700 V         (whole run after start-up)
%   DC bus back inside +/-1 % within 200 ms of each disturbance
%

xp = intParams();
g  = @(n) logsout.get(n).Values;

% This run's own parameters (scenario overrides applied), and the first
% protection event: the trip, or the grid breaker opening. The normal bus and
% recovery checks stop there; protectionMetrics takes over after it.
xs = xp;
for j = 1:2:numel(s.set)
    f  = strsplit(char(s.set{j}), '.');
    xs = setfield(xs, f{:}, s.set{j+1}); %#ok<SFLD>
end
% When the trip ACTUALLY fired, from the logged trip line: the stand-in Step at
% xs.trip.t, or Redhwan's relay on its own (5 Oct). Inf = never.
tt = xs.trip.t;
if any(string(logsout.getElementNames) == "trip")
    tr = g('trip');  k = find(tr.Data(:) > 0.5, 1);
    if isempty(k), tt = Inf; else, tt = tr.Time(k); end
end
r.t_trip = tt;
% A trip nobody asked for (no stand-in trip, no grid opening) is a nuisance trip.
asked = xs.trip.t < s.T || xs.pcc.grid.t < s.T;
r.nuisance_trip = ~asked && tt < s.T;
tProt = min([tt, xs.pcc.grid.t, s.T]);

vdc = g('v_dc');  t = vdc.Time;  v = vdc.Data(:);
ipv = g('i_pv').Data(:);  iw = g('i_wind').Data(:);  ii = g('i_inv').Data(:);
tl  = g('inv_tlm');
i2  = rows(tl.i2_abc);  vab = rows(tl.v_abc);  t2 = tl.i2_abc.Time;
idq = rows(tl.i_dq);  idr = rows(tl.i_dq_ref);  tq = tl.i_dq.Time;

w  = s.window;
m  = t  >= w(1) & t  < w(2);
m2 = t2 >= w(1) & t2 < w(2);
mq = tq >= w(1) & tq < w(2);

r.name = s.name;

% ---- Power flow: from the energy meters, so exact ---------------------------
E  = g('E');  Ed = rows(E);
we = [max(w(1), E.Time(1)), min(w(2), E.Time(end))];    % float-safe ends
Pw = (interp1(E.Time, Ed, we(2)) - interp1(E.Time, Ed, we(1))) / diff(we);
r.P_pv = Pw(1);  r.P_wind = Pw(2);  r.P_invdc = Pw(3);  r.P_ac = Pw(4);
r.P_bal = r.P_pv + r.P_wind - r.P_invdc;        % must equal d(1/2 C v^2)/dt
% Reactive power from the smooth PCC signals (grid-side current is filtered).
q = ((vab(:,2)-vab(:,3)).*i2(:,1) + (vab(:,3)-vab(:,1)).*i2(:,2) + ...
     (vab(:,1)-vab(:,2)).*i2(:,3)) / sqrt(3);
r.Q_ac  = mean(q(m2));
r.PF    = r.P_ac / hypot(r.P_ac, r.Q_ac);
r.eff   = r.P_ac / r.P_invdc;                 % DC in -> grid out, bridge + LCL
r.S_pu  = hypot(r.P_ac, r.Q_ac) / 150e3;

% ---- DC bus -----------------------------------------------------------------
r.Vdc_mean  = mean(v(m));
r.Vdc_pp    = max(v(m)) - min(v(m));          % ripple in the window
pre = t < tProt;                              % normal operation only
r.Vdc_max   = max(v(pre));
r.Vdc_min   = min(v(pre));
r.dev_max   = max(abs(v(pre) - xp.Vdc_ref));
r.dev_pct   = 100*r.dev_max/xp.Vdc_ref;
r.pass_dev  = r.dev_pct < 5;

% Recovery: for each disturbance (t = 0 start-up, and every step in G or
% v_wind), how long until v_dc is back inside +/-1 % and stays there, up to
% the next event or the end of the run. v_dc is slow (C = 44 mF), so filter
% it only lightly (1 ms moving mean) to strip the switching ripple.
tg  = (0:1e-3:s.T)';
ev  = unique([0; tg(find(diff(s.G(tg)) ~= 0 | diff(s.v_wind(tg)) ~= 0) + 1)]);
ev  = ev(ev < tProt);
vf  = movmean(v, round(1e-3/median(diff(t))));
band = 0.01*xp.Vdc_ref;
r.events   = ev';
r.recover  = nan(size(ev'));
for k = 1:numel(ev)
    tEnd = tProt; if k < numel(ev), tEnd = ev(k+1); end
    seg  = t >= ev(k) & t < tEnd;
    ts   = t(seg); out = abs(vf(seg) - xp.Vdc_ref) > band;
    if ~any(out),              r.recover(k) = 0;
    elseif out(end),           r.recover(k) = Inf;          % never came back
    else,                      r.recover(k) = ts(find(out, 1, 'last') + 1) - ev(k);
    end
end
r.pass_recover = all(r.recover <= 0.200);

% ---- Current loop: is Id tracking what the DC loop asks for? ---------------
r.Id_ref  = mean(idr(mq,1));
r.Id      = mean(idq(mq,1));
r.Iq      = mean(idq(mq,2));
r.Id_clip = max(g('Id_ref').Data) >= xp.dc.Id_max - 1e-6;  % DC loop hit 150 kVA

% ---- Grid current quality: phase a of i2 over the window ------------------
[r.THD50, r.THDtot, r.I1_pk, r.h] = thd(i2(m2,1), median(diff(t2)), 50);
r.pass_thd = r.THDtot < 5;

% ---- PLL vs the ideal angle ----------------------------------------------
th  = tl.theta_pll;  thi = g('theta_ideal');
% Compare at the middle of each 100 us control period, so floating-point
% jitter in the two logs' time stamps can't pick the wrong sample.
tc  = (xp.Ts_ctrl/2 : xp.Ts_ctrl : th.Time(end))';
e   = wrapPi(interp1(th.Time, th.Data(:), tc, 'previous') - ...
             interp1(thi.Time, thi.Data(:), tc, 'previous'));
th  = struct('Time', tc);
keep = th.Time > 0.002;
r.pll_err_max_deg = max(abs(rad2deg(e(keep))));
wh  = g('w_hat');
r.f_min = min(wh.Data)/(2*pi);  r.f_max = max(wh.Data)/(2*pi);

r.pass = r.pass_dev && r.pass_recover && (r.pass_thd || r.S_pu < 0.5) && ~r.nuisance_trip;
% SFS angle in the steady window, if the model has SFS (logged as theta_sfs)
if any(string(logsout.getElementNames) == "theta_sfs")
    ths = g('theta_sfs');  r.theta_sfs_deg = rad2deg(mean(ths.Data(ths.Time >= w(1) & ths.Time < w(2))));
end

% ---- Protection path, if this run has a trip or opens the grid -------------
if tProt < s.T
    r.prot = protectionMetrics(g, t, v, tl, wh, xs, xp, s, tt);
    r.pass = r.pass && r.prot.pass;
end
end

function p = protectionMetrics(g, t, v, tl, wh, xs, xp, s, tt)
% What a trip must achieve, measured. Times are ms after the trip.
%   inverter current |i_dq| below 5 % of rated, PV and wind currents below 1 A
%   (all as 1 ms averages: the bridge and boost currents are chopped), and the
%   bus inside +/-5 % from the trip to the end. The inverter current drops in
%   ~2 ms but keeps a ~5 A tail that fades with Duc's current-loop integrator
%   (zero at R/L ~ 14 rad/s, ~70 ms), so a tighter threshold measures the tail.
% If the grid breaker opened first (an island), also the PCC voltage and the
% PLL frequency while islanded, and how fast the trip de-energises the island.
ti = xs.pcc.grid.t;
p.t_trip = tt;  p.t_island = ti;  if ti >= s.T, p.t_island = NaN; end
p.detect_ms = 1e3*(tt - p.t_island);                     % island -> trip (relay or stand-in); NaN if no island
if ~(tt < s.T)
    % The island was never tripped: report how it sat, and fail.
    vab = rows(tl.v_abc);  t2 = tl.v_abc.Time;  n20 = round(0.02/median(diff(t2)));
    vr  = sqrt(movmean(vab(:,1).^2, n20));  isl = t2 >= ti + 0.02;
    p.Vpcc_island_pct = 100*[min(vr(isl)) max(vr(isl))]/(xp.Vgd/sqrt(2));
    fh = wh.Data(:)/(2*pi);  p.f_island = [min(fh(wh.Time >= ti)) max(fh(wh.Time >= ti))];
    p.pass = false;
    return
end
offAfter = @(tx, x, lim) 1e3*settle(tx, x, lim, tt);

idq = rows(tl.i_dq);  tq = tl.i_dq.Time;  n1 = round(1e-3/median(diff(tq)));
p.i_inv_off_ms  = offAfter(tq, movmean(hypot(idq(:,1), idq(:,2)), n1), 0.05*xp.dc.Id_max);
p.i_inv_tail_A  = mean(hypot(idq(tq >= tt+0.02 & tq < tt+0.03, 1), idq(tq >= tt+0.02 & tq < tt+0.03, 2)));

pv = g('i_pv');  wd = g('i_wind');
p.i_pv_off_ms   = offAfter(pv.Time, movmean(pv.Data(:), round(1e-3/median(diff(pv.Time)))), 1);
p.i_wind_off_ms = offAfter(wd.Time, movmean(wd.Data(:), round(1e-3/median(diff(wd.Time)))), 1);

after = t >= tt;
p.Vdc_after     = [min(v(after)) max(v(after))];
p.dev_after_pct = 100*max(abs(v(after) - xp.Vdc_ref))/xp.Vdc_ref;

% PCC voltage: per-cycle (20 ms) RMS of phase a, and its peak envelope.
vab = rows(tl.v_abc);  t2 = tl.v_abc.Time;  n20 = round(0.02/median(diff(t2)));
vr  = sqrt(movmean(vab(:,1).^2, n20));
Vn  = xp.Vgd/sqrt(2);                                    % 230.9 V rms nominal
p.Vpcc_pre_pct = 100*interp1(t2, vr, min(tt, ti) - 0.001)/Vn;
p.Vpcc_off_ms  = offAfter(t2, movmax(max(abs(vab), [], 2), n20), 0.05*xp.Vgd);
if ~isnan(p.t_island)
    isl = t2 >= ti + 0.02 & t2 < tt - 0.01;              % after one cycle, before the
                                                         % 20 ms RMS window sees the trip
    p.Vpcc_island_pct = 100*[min(vr(isl)) max(vr(isl))]/Vn;
    fh  = wh.Data(:)/(2*pi);  mi = wh.Time >= ti & wh.Time < tt;
    p.f_island = [min(fh(mi)) max(fh(mi))];
end
p.pass = p.i_inv_off_ms < 20 && p.i_pv_off_ms < 20 && p.i_wind_off_ms < 20 ...
         && p.dev_after_pct < 5;
end

function ts = settle(tx, x, lim, t0)
% Time from t0 until |x| is below lim and stays there; Inf if it never does.
k  = tx >= t0;  tk = tx(k);  above = abs(x(k)) >= lim;
if ~any(above),   ts = 0;
elseif above(end), ts = Inf;
else,             ts = tk(find(above, 1, 'last') + 1) - t0;
end
end

function x = rows(ts)
% Telemetry arrives as N x k or k x 1 x N depending on the block; make it N x k.
x = squeeze(ts.Data);
if size(x,1) ~= numel(ts.Time), x = x.'; end
end

function e = wrapPi(e)
e = mod(e + pi, 2*pi) - pi;
end

function [thd50, thdTot, I1, h] = thd(x, dt, nmax)
% Window must hold a whole number of 50 Hz cycles (the scenario windows do),
% so the fundamental lands exactly on a bin and there's no leakage.
N  = numel(x);
X  = abs(fft(x - mean(x)))/N*2;
df = 1/(N*dt);
k1 = round(50/df) + 1;
I1 = X(k1);
kh = (2:nmax)*(k1-1) + 1;
h  = X(kh)/I1*100;                         % % of fundamental, orders 2..nmax
thd50  = sqrt(sum(X(kh).^2))/I1*100;
half   = 2:floor(N/2);
thdTot = sqrt(sum(X(half).^2) - I1^2)/I1*100;   % everything to Nyquist (100 kHz)
end
