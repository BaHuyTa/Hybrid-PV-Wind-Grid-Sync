% inv_current_loop_check.m
% Does the dq current loop meet its graded spec?
%
%   inner current loop settling < 2 ms, overshoot < 10%   (README success criteria)
%
% Run on invPlantAvg, the averaged model - which is the point of having one.
% The bridge and the modulator are ideal here, so what is measured is the loop
% itself rather than switching artefacts. The switched model answers a different
% question (THD) and inv_thd_check asks it there.
%
% Three numbers per scenario, kept separate on purpose:
%   settling    to within 2% of the value actually reached - a dynamics number
%   overshoot   relative to the step size
%   residual    how far the settled value sits from the command, as a fraction
%               of RATED current. There is a slow tail of about 0.8% of rated
%               decaying at ~64 ms (the filter's own R/L), left over from the
%               pole-zero cancellation once the one-sample delay is included.
%               Rolling it into the settling number would make a small step look
%               like a failure and a large one look fine, which says nothing
%               about the loop. It is well inside what the DC-link loop above
%               will absorb.
%
% Scenarios:
%   1. Id step to half rated       - the nominal tracking case
%   2. Id step half -> full rated  - the same test with the command near the ceiling
%   3. Iq step                     - the reactive axis tracks too
%   4. Iq step, watching Id        - cross-coupling: how far does the d axis move
%                                    when q is disturbed? This is what the wL
%                                    decoupling terms are for, and the only
%                                    honest way to show they work.
%
% Output: results/inv_current_loop.png (gitignored - regenerate, don't commit)
%
% Usage:
%   addpath(genpath('models'));
%   inv_current_loop_check
%
% Owner: Duc Pham

clear; clc;
ip   = invParams();
here = fileparts(mfilename('fullpath'));
outdir = fullfile(here, 'results');
if ~isfolder(outdir), mkdir(outdir); end

t_step = 0.04;                       % step well after the grid angle has settled
t      = (0:ip.Ts_power:0.06)';
step   = double(t >= t_step);
Ihalf  = 0.5*ip.I_pk;

scen = { ...
  'Id 0 -> 50% rated',   Ihalf*step,                 0*step,            'd'; ...
  'Id 50% -> 100%',      Ihalf + Ihalf*step,         0*step,            'd'; ...
  'Iq 0 -> 25% rated',   0*step,                     0.25*ip.I_pk*step, 'q'; ...
  'Iq step, watch Id',   Ihalf*ones(size(t)),        0.25*ip.I_pk*step, 'd'};

TOL_SETTLE = 2e-3;      % s
TOL_OS     = 10;        % %
TOL_RESID  = 1.0;       % % of rated peak current
TOL_XCOUPL = 5.0;       % % of rated peak current

fprintf('=== dq current loop, averaged model ===\n');
fprintf('  bandwidth %g Hz | Kp %.4f V/A | Ki %.2f V/(A.s) | Ts_ctrl %g us\n', ...
        ip.f_i_bw, ip.Kp_i, ip.Ki_i, ip.Ts_ctrl*1e6);
fprintf('  rated peak current %.1f A | PI authority %.1f V of the %.1f V the bridge makes\n\n', ...
        ip.I_pk, ip.V_pi_max, ip.V_max);
fprintf('  %-22s %9s %9s %11s\n', 'scenario', 'settle', 'overshoot', 'residual');
fprintf('  %s\n', repmat('-', 1, 56));

R = struct('name',{},'t',{},'idq',{},'ref',{},'vdq',{});
fails = {};
for k = 1:size(scen,1)
    tl  = invSim(t, struct('model','invPlantAvg', ...
                           'Id_ref', scen{k,2}, 'Iq_ref', scen{k,3}));
    tt  = tl.i_dq.Time;
    idq = tl.i_dq.Data;
    ax  = 1 + strcmp(scen{k,4}, 'q');                  % 1 = d, 2 = q
    y   = idq(:, ax);
    ref = interp1(t, scen{k, 1+ax}, tt, 'previous', 'extrap');

    k0   = find(tt >= t_step, 1);
    y0   = ref(k0-1);
    cmd  = ref(end);
    yend = mean(y(end-20:end));

    if abs(cmd - y0) > 1e-6
        % --- a step on this axis: dynamics + accuracy, reported separately
        span = cmd - y0;
        band = abs(y - yend) <= 0.02*abs(span);        % 2% of the value REACHED
        bad  = find(~band); bad = bad(bad >= k0);
        if isempty(bad)
            ts_set = 0;
        elseif bad(end)+1 > numel(tt)
            ts_set = Inf;
        else
            ts_set = tt(bad(end)+1) - t_step;
        end
        ov    = 100*max(0, sign(span)*(max(sign(span)*y(k0:end)) - sign(span)*yend))/abs(span);
        resid = 100*(yend - cmd)/ip.I_pk;
        ok    = ts_set < TOL_SETTLE && ov < TOL_OS && abs(resid) < TOL_RESID;
        fprintf('  %-22s %6.2f ms %7.1f %% %8.2f %%%s\n', scen{k,1}, ts_set*1e3, ov, resid, ...
                tern(ok, '', '   <-- FAIL'));
        if ~ok, fails{end+1} = scen{k,1}; end %#ok<SAGROW>
    else
        % --- this axis is NOT stepped: how far does the other axis push it?
        base = mean(y(k0-20:k0-1));
        dev  = 100*max(abs(y(k0:end) - base))/ip.I_pk;
        ok   = dev < TOL_XCOUPL;
        fprintf('  %-22s %9s %9s %8.2f %% (cross-coupling)%s\n', scen{k,1}, '-', '-', dev, ...
                tern(ok, '', '   <-- FAIL'));
        if ~ok, fails{end+1} = scen{k,1}; end %#ok<SAGROW>
    end

    R(k).name = scen{k,1}; R(k).t = tt; R(k).idq = idq;
    R(k).ref  = [interp1(t, scen{k,2}, tt, 'previous', 'extrap'), ...
                 interp1(t, scen{k,3}, tt, 'previous', 'extrap')];
    R(k).vdq  = tl.v_dq_cmd.Data;
end
fprintf('\n  tolerances: settle < %g ms, overshoot < %g %%, residual < %g %% of rated,\n', ...
        TOL_SETTLE*1e3, TOL_OS, TOL_RESID);
fprintf('              cross-coupling < %g %% of rated\n\n', TOL_XCOUPL);

%% ---- voltage headroom --------------------------------------------------
% Steady state must fit inside what the bridge can make. The transient may not,
% and that is expected: during a full-rated step the loop asks for everything it
% has. A circular |V_dq| limiter belongs in the MODULATOR, which is the only
% block that knows the modulation scheme and therefore the real ceiling - see
% README, open items.
vmag = sqrt(R(2).vdq(:,1).^2 + R(2).vdq(:,2).^2);
ss   = vmag(end-200:end);
fprintf('=== voltage command vs what the bridge can make ===\n');
fprintf('  |V_dq| steady state   %6.1f V   (%.0f %% of ceiling)\n', mean(ss), 100*mean(ss)/ip.V_max);
fprintf('  |V_dq| transient peak %6.1f V   (%.0f %% of ceiling)\n', max(vmag), 100*max(vmag)/ip.V_max);
fprintf('  SVPWM ceiling         %6.1f V   (V_dc/sqrt(3))\n', ip.V_max);
if mean(ss) > ip.V_max
    fails{end+1} = 'steady-state command exceeds the modulator ceiling';
end
if max(vmag) > ip.V_max
    fprintf('  NOTE: the transient asks for %.0f %% more than the bridge can make for\n', ...
            100*(max(vmag)/ip.V_max - 1));
    fprintf('        %.2f ms. SVPWM will overmodulate briefly. Acceptable here;\n', ...
            ip.Ts_ctrl*sum(vmag > ip.V_max)*1e3);
    fprintf('        a circular limiter in the modulator removes it.\n');
end

%% ---- slew limit: the constraint this puts on the LCL -------------------
fprintf('\n=== what this means for the filter inductance ===\n');
fprintf('  voltage left for control  %.1f V  (bridge %.1f - grid %.1f)\n', ...
        ip.V_pi_max, ip.V_max, ip.V_grid_pk);
fprintf('  fastest di/dt             %.0f A/ms\n', ip.didt_max/1e3);
fprintf('  0 -> rated slew, best case %.2f ms  (spec allows 2 ms)\n', ip.t_slew_full*1e3);
fprintf('  => L_f ceiling for a full-rated step in 2 ms: %.2f mH (now %.2f mH)\n\n', ...
        1e3*ip.V_pi_max*2e-3/ip.I_pk, ip.L_f*1e3);

%% ---- figure ------------------------------------------------------------
f = figure('Color','w','Position',[100 100 1100 780]);
tiledlayout(f, 4, 1, 'TileSpacing','compact', 'Padding','compact');
for k = 1:4
    nexttile;
    tms = (R(k).t - t_step)*1e3;
    plot(tms, R(k).idq(:,1), 'LineWidth',1.4); hold on;
    plot(tms, R(k).idq(:,2), 'LineWidth',1.4);
    plot(tms, R(k).ref(:,1), '--', 'LineWidth',1);
    plot(tms, R(k).ref(:,2), '--', 'LineWidth',1);
    grid on; xlim([-1 5]); ylabel('A');
    legend('I_d','I_q','I_d^{ref}','I_q^{ref}','Location','eastoutside');
    title(R(k).name);
    if k == 4, xlabel('time from step (ms)'); end
end
try, theme(f,'light'); catch, end
exportgraphics(f, fullfile(outdir,'inv_current_loop.png'), 'Resolution', 130);
fprintf('Figure written to %s\n', outdir);

if ~isempty(fails)
    error('inv_current_loop_check:failed', 'Spec not met: %s', strjoin(fails, '; '));
end
fprintf('\n  All checks passed.\n');

% -------------------------------------------------------------------------
function s = tern(c, a, b)
if c, s = a; else, s = b; end
end
