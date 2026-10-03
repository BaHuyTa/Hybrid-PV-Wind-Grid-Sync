function protection_figures()
%PROTECTION_FIGURES Regenerate the anti-islanding evidence figures.
%   Produces four figures from the current rig:
%
%     fig1_phase_reset.png     - the phase reference resetting at each PCC
%                                voltage zero crossing
%     fig2_current_fft.png     - spectrum of the injected current, showing
%                                the fundamental at pp.Ipvmax and the THD
%     fig3_island_event.png    - grid current collapsing at the island
%     fig4_island_frequency.png- PCC frequency across the island, measured
%                                independently of the model's own estimator
%
%   Figures are written to results/. The model on disk is never modified:
%   run settings go through Simulink.SimulationInput and the one signal
%   logging change is made to the in-memory copy only.
%
%   HISTORY. These four figures were first taken on SFS_test1, where fpcc
%   was a constant placeholder and the positive-feedback loop was therefore
%   open. Re-running them against SFS gives a different fig3 and fig4,
%   because the frequency now runs away and the inverter trips: that is the
%   intended change, not a regression. The Week 7 and Week 8 journal copies
%   are preserved under their own names in results/journal_week7 and
%   results/journal_week8 and are not overwritten by this script.
%
%   Every title here is written from a measurement rather than asserting a
%   fixed claim, so the figure cannot contradict the model it was taken on.
%
%   Usage:
%       protection_figures
%
%   See also PROTECTIONPARAMS, RLCTESTLOAD, MAKE_FIG5, NDZ_SWEEP

mdl  = 'SFS';
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(root, 'models', 'protection'));
outdir = fullfile(root, 'results');
if ~isfolder(outdir), mkdir(outdir); end

pp = protectionParams();
assignin('base', 'pp', pp);

if ~bdIsLoaded(mdl)
    load_system(fullfile(root, 'models', 'protection', mdl));
end
enablePhaseLogging(mdl);
enableTripLogging(mdl);
enableFestLogging(mdl);

% Run A: short, full resolution, entirely grid-connected.
%        Feeds the phase-reset and spectrum figures.
inA = Simulink.SimulationInput(mdl);
inA = inA.setModelParameter('StopTime', '0.6', ...
                            'SimscapeLogType', 'all', ...
                            'SimscapeLogDecimation', 1, ...
                            'SignalLogging', 'on', ...
                            'SignalLoggingName', 'logsout');
outA = sim(inA);

% Run B: full length, decimated, covers the island event.
inB = Simulink.SimulationInput(mdl);
inB = inB.setModelParameter('StopTime', num2str(pp.t_stop), ...
                            'SimscapeLogType', 'all', ...
                            'SimscapeLogDecimation', 50, ...
                            'SignalLogging', 'on', ...
                            'SignalLoggingName', 'logsout');
outB = sim(inB);

% When the loop is closed the inverter trips partway through run B, and both
% island figures need to know where. Empty on a model that never trips.
tTrip = tripTime(outB, pp);

figure1_phaseReset(outA, pp, outdir);
figure2_currentFFT(outA, pp, outdir);
figure3_islandEvent(outB, pp, outdir, tTrip);
figure4_islandFrequency(outB, pp, outdir, tTrip);

fprintf('\nFigures written to %s\n', outdir);
end

% ---------------------------------------------------------------------
function figure4_islandFrequency(out, pp, outdir, tTrip)
%FIGURE4_ISLANDFREQUENCY PCC frequency per cycle, across the island event.
%   Grid-connected the grid pins the frequency at f_n. Once islanded the
%   load must satisfy the phase the SFS block imposes on the injected
%   current, which forces it off resonance.
%
%   The frequency here is recovered from the PCC voltage zero crossings by
%   this script, independently of the model's own FreqEstimator. That makes
%   the figure a check on the estimator rather than a restatement of it.
sl = out.simlog;
t = sl.RLC_Load.R_load.v.series.time;
v = sl.RLC_Load.R_load.v.series.values;

% per-cycle frequency from rising zero crossings, linearly interpolated
tu = linspace(t(1), t(end), 2000001);
vu = interp1(t, v, tu);
s  = sign(vu);
k  = find(s(1:end-1) < 0 & s(2:end) >= 0);
tc = tu(k) - vu(k).*(tu(k+1) - tu(k))./(vu(k+1) - vu(k));
f  = 1./diff(tc);
tf = tc(2:end);

pre = mean(f(tf > 0.50 & tf < 0.95));

% Past the trip the inverter is disconnected and the "frequency" is ringdown
% on a dead circuit, so plot only up to it.
if isempty(tTrip)
    keep = true(size(tf));
else
    keep = tf <= tTrip;
end

fg = newFigure([100 100 900 400]);
h1 = plot(tf(keep), f(keep), 'LineWidth', 1.3); grid on; hold on

% Overlay the estimate the relay acts on. The two are measured the same way
% - one cycle between zero crossings - but this script reads a decimated log
% and attributes each cycle to the instant it ENDS, so near the trip, where
% the frequency is climbing within the cycle, the independent trace reads
% below the relay's. Showing both is what makes the trip instant explicable.
fe = getLogged(out, 'f_est');
h2 = [];
if ~isempty(fe)
    m  = true(size(fe.Values.Time));
    if ~isempty(tTrip), m = fe.Values.Time <= tTrip; end
    h2 = plot(fe.Values.Time(m), fe.Values.Data(m), '-', ...
        'LineWidth', 1.1, 'Color', [0.85 0.33 0.10]);
end
xline(pp.t_island, 'r--', 'LineWidth', 1.4, 'Label', 'island', ...
    'LabelOrientation', 'horizontal', 'LabelVerticalAlignment', 'bottom', ...
    'LabelHorizontalAlignment', 'left');
yline(pp.f_n, ':', 'LineWidth', 1.1, 'Label', 'nominal', ...
    'Color', [0.30 0.30 0.30], 'LabelHorizontalAlignment', 'left');
yline(pp.f_max, 'm--', 'LineWidth', 1.2, 'Label', 'over-frequency trip', ...
    'Color', [0.55 0 0.55], 'LabelHorizontalAlignment', 'center', ...
    'LabelVerticalAlignment', 'bottom');
xlabel('Time (s)');
ylabel('PCC frequency (Hz)');

% Describe what was measured. With the loop closed the frequency diverges to
% a threshold; with fpcc held constant it settles short of one.
if isempty(tTrip)
    post = mean(f(tf > pp.t_island + 0.05 & tf < pp.t_island + 0.50));
    ylim([pp.f_n - 0.5, max(pp.f_max + 0.3, pp.f_n + 0.8)]);
    title(sprintf(['PCC frequency across the island: %.4f Hz grid-connected, ' ...
        '%.4f Hz islanded\nthe SFS phase advance forces the load off resonance, ' ...
        'but the frequency settles short of the %g Hz threshold and never trips'], ...
        pre, post, pp.f_max));
    fprintf('fig4: PCC frequency %.4f Hz connected -> %.4f Hz islanded, NO TRIP (band %.1f-%.1f Hz)\n', ...
        pre, post, pp.f_min, pp.f_max);
else
    % The relay's own estimate at the trip is the number that matters: it is
    % what crossed the threshold.
    if isempty(fe)
        fTrip = f(find(keep, 1, 'last'));
    else
        fTrip = fe.Values.Data(find(m, 1, 'last'));
    end
    plot(tTrip, fTrip, 'v', 'MarkerSize', 10, 'MarkerFaceColor', [0.10 0.70 0.25], ...
        'MarkerEdgeColor', 'k');
    ylim([pp.f_n - 0.5, max(fTrip, pp.f_max) + 0.5]);
    xlim([0.8 min(tTrip + 0.15, tf(end))]);
    title(sprintf(['PCC frequency across the island: %.4f Hz grid-connected, ' ...
        'driven to %.2f Hz once islanded\npositive feedback diverges to the %g Hz ' ...
        'threshold; trip at t = %.3f s, detection %.0f ms'], ...
        pre, fTrip, pp.f_max, tTrip, 1000*(tTrip - pp.t_island)));
    if ~isempty(h2)
        legend([h1 h2], {'measured here from the PCC voltage (decimated log)', ...
            'the model''s FreqEstimator - what the relay acts on'}, ...
            'Location', 'northwest', 'FontSize', 9);
    end
    fprintf('fig4: PCC frequency %.4f Hz connected -> %.2f Hz at trip (band %.1f-%.1f Hz)\n', ...
        pre, fTrip, pp.f_min, pp.f_max);
end
styleAxes(findobj(fg, 'Type', 'axes'));
saveFig(fg, outdir, 'fig4_island_frequency.png');
end

% ---------------------------------------------------------------------
function fg = newFigure(pos)
%NEWFIGURE A white figure that the MATLAB desktop theme cannot reach.
%   Left to itself a dark desktop theme leaks into the export - black
%   canvas, grey text - which is illegible on a white page. Building the
%   figure invisible with InvertHardcopy off, and setting every colour
%   explicitly in STYLEAXES, keeps the output independent of the desktop.
%   Do NOT call theme() to fix this: it can block the session when driven
%   non-interactively.
fg = figure('Color', 'w', 'Position', pos, 'Visible', 'off', ...
            'InvertHardcopy', 'off');
end

% ---------------------------------------------------------------------
function styleAxes(ax)
%STYLEAXES Force axes, text and legend to print black on white.
%   Call after the title, labels and legend exist - it restyles them.
for a = reshape(ax, 1, [])
    set(a, 'Color', 'w', 'XColor', 'k', 'YColor', 'k', ...
           'GridColor', [0.72 0.72 0.72], 'GridAlpha', 0.9, ...
           'FontSize', 11, 'LineWidth', 1.0, 'Layer', 'top');
    set([get(a, 'Title'), get(a, 'XLabel'), get(a, 'YLabel')], 'Color', 'k');
    lg = get(a, 'Legend');
    if ~isempty(lg)
        set(lg, 'TextColor', 'k', 'Color', 'w', 'EdgeColor', [0.45 0.45 0.45]);
    end
end
end

% ---------------------------------------------------------------------
function saveFig(fg, outdir, name)
%SAVEFIG Export at 200 dpi on a white background, then close.
exportgraphics(fg, fullfile(outdir, name), 'Resolution', 200, ...
    'BackgroundColor', 'white');
close(fg);
end

% ---------------------------------------------------------------------
function enableFestLogging(mdl)
%ENABLEFESTLOGGING Mark the FreqEstimator output for logging as "f_est".
%   This is the estimate the relay actually acts on. Logging it lets fig4
%   compare it against a frequency recovered independently from the voltage.
blk = [mdl '/FreqEstimator'];
if getSimulinkBlockHandle(blk) <= 0, return, end
ph = get_param(blk, 'PortHandles');
set_param(ph.Outport(1), 'DataLogging', 'on', ...
                         'DataLoggingNameMode', 'Custom', ...
                         'DataLoggingName', 'f_est');
end

% ---------------------------------------------------------------------
function s = getLogged(out, name)
%GETLOGGED Logged signal by name, or empty if it is not there.
%   A name can be carried by more than one logged signal - make_fig5 tags
%   the ClampBand output inside FreqEstimator as "f_est" and this script
%   tags the subsystem outport, which is the same line - and get() then
%   hands back a Dataset rather than an element. They are the same signal,
%   so take the first.
s = [];
if ~isprop(out, 'logsout') && ~isfield(out, 'logsout'), return, end
if ~any(strcmp(out.logsout.getElementNames(), name)), return, end
s = out.logsout.get(name);
if isa(s, 'Simulink.SimulationData.Dataset')
    s = s.getElement(1);
end
end

% ---------------------------------------------------------------------
function enableTripLogging(mdl)
%ENABLETRIPLOGGING Mark the TripLogic output for logging as "trip".
%   Absent on SFS_test1, which has no trip logic, so this is tolerant.
blk = [mdl '/TripLogic'];
if getSimulinkBlockHandle(blk) <= 0, return, end
ph = get_param(blk, 'PortHandles');
set_param(ph.Outport(1), 'DataLogging', 'on', ...
                         'DataLoggingNameMode', 'Custom', ...
                         'DataLoggingName', 'trip');
end

% ---------------------------------------------------------------------
function t = tripTime(out, pp)
%TRIPTIME First instant the trip latch sets, or empty if it never does.
t  = [];
tr = getLogged(out, 'trip');
if isempty(tr), return, end
k = find(double(tr.Values.Data) > 0.5, 1);
if isempty(k), return, end
t = tr.Values.Time(k);
fprintf('trip at t = %.4f s (detection %.1f ms after the island)\n', ...
    t, 1000*(t - pp.t_island));
end

% ---------------------------------------------------------------------
function enablePhaseLogging(mdl)
%ENABLEPHASELOGGING Mark the phase-ramp signal for logging as "tau".
blk = find_system([mdl '/SFS_Controller'], 'BlockType', 'DiscreteIntegrator');
if isempty(blk)
    blk = find_system([mdl '/SFS_Controller'], 'BlockType', 'Integrator');
end
assert(~isempty(blk), 'No integrator found inside SFS_Controller.');
ph = get_param(blk{1}, 'PortHandles');
set_param(ph.Outport(1), 'DataLogging', 'on', ...
                         'DataLoggingNameMode', 'Custom', ...
                         'DataLoggingName', 'tau');
end

% ---------------------------------------------------------------------
function figure1_phaseReset(out, pp, outdir)
%FIGURE1_PHASERESET Actual phase ramp against a correctly locked ramp.
tau = out.logsout.get('tau');
t = tau.Values.Time;
v = tau.Values.Data;

w  = t >= 0.50 & t <= 0.58;          % four cycles at 50 Hz
tw = t(w);
vw = v(w);
expected = mod(tw, 1/pp.f_n);        % what a ramp locked to V_PCC looks like

% Label according to what was actually measured, so the figure cannot
% contradict itself once the reset is working.
rise   = max(vw) - min(vw);
locked = rise < 1.5/pp.f_n;

f = newFigure([100 100 900 380]);
plot(tw, vw, 'LineWidth', 1.6); hold on
plot(tw, expected, '--', 'LineWidth', 1.4);
grid on
xlabel('Time (s)');
ylabel('Phase reference \tau (s)');
if locked
    title(sprintf(['Phase reference locked to the PCC voltage zero crossings\n' ...
        'resets every %.2f ms against a %.0f ms period; measured and expected coincide'], ...
        rise*1000, 1000/pp.f_n));
    legend({'\tau as measured', ...
            sprintf('\\tau expected if locked (%g Hz)', pp.f_n)}, ...
            'Location', 'northwest');
else
    title(sprintf(['Phase reference free-runs instead of resetting\n' ...
        'rises %.3f s across this window; a locked ramp would reset every %.0f ms'], ...
        rise, 1000/pp.f_n));
    legend({'\tau as measured (never resets)', ...
            sprintf('\\tau if locked to V_{PCC} zero crossings (%g Hz)', pp.f_n)}, ...
            'Location', 'northwest');
end
styleAxes(findobj(f, 'Type', 'axes'));
saveFig(f, outdir, 'fig1_phase_reset.png');
fprintf('fig1: tau rises %.4f s over a %.2f s window (a reset ramp would peak at %.4f s)\n', ...
    max(vw) - min(vw), tw(end) - tw(1), 1/pp.f_n);
end

% ---------------------------------------------------------------------
function figure2_currentFFT(out, pp, outdir)
%FIGURE2_CURRENTFFT Spectrum of the injected current, uniformly resampled.
%   Resampling matters. Solver steps are non-uniform, and running an FFT
%   straight off them aliases the waveform into apparent distortion - the
%   mistake that produced a spurious 45.9% THD reading.
sl = out.simlog;
t = sl.Inverter_CCS.i.series.time;
i = sl.Inverter_CCS.i.series.values;

% The Simscape log retains only its last N points, and how much simulated
% time that covers depends on how hard the solver worked. Take the largest
% whole number of cycles that actually fits.
Ts   = 1e-5;
span = (t(end) - 0.002) - t(1);
ncyc = floor(span*pp.f_n);
assert(ncyc >= 2, ...
    'Logged range spans only %.4f s (%.1f cycles); need at least 2.', span, span*pp.f_n);
ncyc = min(ncyc, 8);
t2 = t(end) - 0.002;
t1 = t2 - ncyc/pp.f_n;
fprintf('fig2: using %d cycles from %.4f-%.4f s\n', ncyc, t1, t2);

tu = t1:Ts:t2;
iu = interp1(t, i, tu, 'linear');

N   = numel(iu);
Y   = fft(iu - mean(iu));
mag = abs(Y(1:floor(N/2))) * 2/N;
fr  = (0:floor(N/2)-1) / (N*Ts);

[~, k] = min(abs(fr - pp.f_n));
fund = mag(k);
h = mag;
h(max(1, k-2):min(numel(h), k+2)) = 0;
thd = 100 * sqrt(sum(h.^2)) / fund;

% Log magnitude. The harmonics sit ~400x below the fundamental, so on a
% linear axis every component except the 50 Hz spike is sub-pixel.
f = newFigure([100 100 900 400]);
semilogy(fr, max(mag, 1e-6), 'LineWidth', 1.0); hold on
plot(fr(k), fund, 'o', 'MarkerSize', 8, 'LineWidth', 1.5);
grid on
xlim([0 1.2e4]);
ylim([1e-4 1e2]);
xlabel('Frequency (Hz)');
ylabel('Current (A peak) - log scale');
title(sprintf(['Injected current spectrum: fundamental %.2f A at %g Hz, THD %.2f%%\n' ...
    'largest harmonic is %.0fx below the fundamental; cluster near %g kHz is the ' ...
    'control-rate zero-order hold'], ...
    fund, pp.f_n, thd, fund/max(h), 1e-3/pp.Ts));
legend({'spectrum', sprintf('fundamental (%.2f A)', fund)}, 'Location', 'northeast');
styleAxes(findobj(f, 'Type', 'axes'));
saveFig(f, outdir, 'fig2_current_fft.png');
fprintf('fig2: fundamental %.2f A (Ipvmax %.2f), THD %.2f%%\n', fund, pp.Ipvmax, thd);
end

% ---------------------------------------------------------------------
function figure3_islandEvent(out, pp, outdir, tTrip)
%FIGURE3_ISLANDEVENT Grid current and PCC voltage across the island event.
sl = out.simlog;
tg = sl.Grid.i.series.time;
ig = sl.Grid.i.series.values;
tv = sl.RLC_Load.R_load.v.series.time;
vv = sl.RLC_Load.R_load.v.series.values;

rmsIn  = @(t, x, a, b) sqrt(mean(interp1(t, x, linspace(a, b, 20001)).^2));
meanIn = @(t, x, a, b) mean(interp1(t, x, linspace(a, b, 20001)));
pre  = rmsIn(tg, ig, 0.50, 0.95);
post = rmsIn(tg, ig, pp.t_island + 0.05, pp.t_island + 0.50);

% The pre-island RMS is dominated by a DC offset, not by real power exchange.
% A lossless inductor energised at t = 0 keeps its startup DC component
% forever, because nothing in that branch dissipates it.
dc  = meanIn(tg, ig, 0.50, 0.95);
iL0 = pp.Vg_amp/(pp.w_n*pp.L_load);   % steady-state inductor current, peak
fprintf(['fig3: pre-island grid current DC component %.2f A, AC part %.2f A\n' ...
    '      (DC offset expected from energising a lossless inductor: %.2f A)\n'], ...
    dc, sqrt(max(pre^2 - dc^2, 0)), iL0);

f = newFigure([100 100 900 520]);

subplot(2, 1, 1);
plot(tg, ig, 'LineWidth', 0.9); grid on; hold on
xline(pp.t_island, 'r--', 'LineWidth', 1.4, 'Label', 'breaker opens', ...
    'LabelOrientation', 'horizontal', 'LabelVerticalAlignment', 'top', ...
    'LabelHorizontalAlignment', 'left');
if ~isempty(tTrip)
    xline(tTrip, 'Color', [0 0.5 0], 'LineStyle', '--', 'LineWidth', 1.4, ...
        'Label', 'trip', 'LabelOrientation', 'horizontal', ...
        'LabelVerticalAlignment', 'top', 'LabelHorizontalAlignment', 'right');
end
ylabel('Grid current (A)');
title(sprintf('Island at t = %.2f s: grid current %.2f A RMS before, %.4f A after', ...
    pp.t_island, pre, post));

subplot(2, 1, 2);
plot(tv, vv, 'LineWidth', 0.9); grid on; hold on
xline(pp.t_island, 'r--', 'LineWidth', 1.4);
xlabel('Time (s)');
ylabel('V_{PCC} (V)');

% The matched load is the worst case precisely because the voltage does not
% move on islanding. Quantify it rather than asserting it, and separate the
% collapse that follows the trip from the island itself.
vPre  = rmsIn(tv, vv, 0.50, 0.95);
if isempty(tTrip)
    vPost = rmsIn(tv, vv, pp.t_island + 0.05, pp.t_island + 0.50);
    title(sprintf(['PCC voltage %.1f V RMS before, %.1f V after (%.2f%% change): the ' ...
        'matched load is the worst case for detection'], ...
        vPre, vPost, 100*(vPost - vPre)/vPre));
else
    vPost = rmsIn(tv, vv, pp.t_island + 0.005, tTrip - 0.005);
    xline(tTrip, 'Color', [0 0.5 0], 'LineStyle', '--', 'LineWidth', 1.4, ...
        'Label', 'trip', 'LabelOrientation', 'horizontal', ...
        'LabelVerticalAlignment', 'top', 'LabelHorizontalAlignment', 'right');
    title(sprintf(['PCC voltage %.1f V RMS before, %.1f V while islanded (%.2f%% change) ' ...
        '- no voltage signature to detect;\nthe collapse after t = %.3f s is the trip, ' ...
        'not the island'], vPre, vPost, 100*(vPost - vPre)/vPre, tTrip));
end

styleAxes(findobj(f, 'Type', 'axes'));
saveFig(f, outdir, 'fig3_island_event.png');
fprintf('fig3: grid current %.3f A RMS before island, %.4f A after\n', pre, post);
end
