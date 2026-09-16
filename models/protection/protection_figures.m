function protection_figures()
%PROTECTION_FIGURES Regenerate the anti-islanding evidence figures.
%   Produces the three figures used as evidence in the PDLJ Week 6 entry:
%
%     fig1_phase_reset.png  - the phase reference free-running instead of
%                             resetting at each voltage zero crossing
%     fig2_current_fft.png  - spectrum of the injected current, showing the
%                             fundamental at pp.Ipvmax and the true THD
%     fig3_island_event.png - grid current collapsing to zero at the island
%
%   Figures are written to results/. The model on disk is never modified:
%   run settings go through Simulink.SimulationInput and the one signal
%   logging change is made to the in-memory copy only.
%
%   Usage:
%       protection_figures
%
%   See also PROTECTIONPARAMS, RLCTESTLOAD

mdl  = 'SFS_test1';
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
                            'SimscapeLogDecimation', 50);
outB = sim(inB);

figure1_phaseReset(outA, pp, outdir);
figure2_currentFFT(outA, pp, outdir);
figure3_islandEvent(outB, pp, outdir);

fprintf('\nFigures written to %s\n', outdir);
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

f = figure('Color', 'w', 'Position', [100 100 900 380]);
plot(tw, vw, 'LineWidth', 1.6); hold on
plot(tw, expected, '--', 'LineWidth', 1.4);
grid on
xlabel('Time (s)');
ylabel('Phase reference \tau (s)');
title(sprintf(['Phase reference free-runs instead of resetting\n' ...
    'measured rise %.3f s across this window; a locked ramp resets every %.0f ms'], ...
    max(vw) - min(vw), 1000/pp.f_n));
legend({'\tau as measured (never resets)', ...
        sprintf('\\tau if locked to V_{PCC} zero crossings (%g Hz)', pp.f_n)}, ...
        'Location', 'northwest');
exportgraphics(f, fullfile(outdir, 'fig1_phase_reset.png'), 'Resolution', 200);
close(f);
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

Ts   = 1e-5;
ncyc = 4;
t2 = t(end) - 0.005;
t1 = t2 - ncyc/pp.f_n;
assert(t1 >= t(1), 'Logged range too short for %d cycles.', ncyc);

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
f = figure('Color', 'w', 'Position', [100 100 900 400]);
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
exportgraphics(f, fullfile(outdir, 'fig2_current_fft.png'), 'Resolution', 200);
close(f);
fprintf('fig2: fundamental %.2f A (Ipvmax %.2f), THD %.2f%%\n', fund, pp.Ipvmax, thd);
end

% ---------------------------------------------------------------------
function figure3_islandEvent(out, pp, outdir)
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

f = figure('Color', 'w', 'Position', [100 100 900 520]);

subplot(2, 1, 1);
plot(tg, ig, 'LineWidth', 0.9); grid on; hold on
xline(pp.t_island, 'r--', 'LineWidth', 1.4, 'Label', 'breaker opens');
ylabel('Grid current (A)');
title(sprintf('Island at t = %.2f s: grid current %.2f A RMS before, %.4f A after', ...
    pp.t_island, pre, post));

subplot(2, 1, 2);
plot(tv, vv, 'LineWidth', 0.9); grid on; hold on
xline(pp.t_island, 'r--', 'LineWidth', 1.4);
xlabel('Time (s)');
ylabel('V_{PCC} (V)');
title('PCC voltage barely moves: the matched load is the worst case for detection');

exportgraphics(f, fullfile(outdir, 'fig3_island_event.png'), 'Resolution', 200);
close(f);
fprintf('fig3: grid current %.3f A RMS before island, %.4f A after\n', pre, post);
end
