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
r.Vdc_max   = max(v);
r.Vdc_min   = min(v);
r.dev_max   = max(abs(v - xp.Vdc_ref));
r.dev_pct   = 100*r.dev_max/xp.Vdc_ref;
r.pass_dev  = r.dev_pct < 5;

% Recovery: for each disturbance (t = 0 start-up, and every step in G or
% v_wind), how long until v_dc is back inside +/-1 % and stays there, up to
% the next event or the end of the run. v_dc is slow (C = 44 mF), so filter
% it only lightly (1 ms moving mean) to strip the switching ripple.
tg  = (0:1e-3:s.T)';
ev  = unique([0; tg(find(diff(s.G(tg)) ~= 0 | diff(s.v_wind(tg)) ~= 0) + 1)]);
vf  = movmean(v, round(1e-3/median(diff(t))));
band = 0.01*xp.Vdc_ref;
r.events   = ev';
r.recover  = nan(size(ev'));
for k = 1:numel(ev)
    tEnd = s.T; if k < numel(ev), tEnd = ev(k+1); end
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

r.pass = r.pass_dev && r.pass_recover && (r.pass_thd || r.S_pu < 0.5);
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
