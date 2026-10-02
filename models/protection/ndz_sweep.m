function ndz_sweep(qfRows)
%NDZ_SWEEP Map the non-detection zone against load detuning and quality factor.
%   NDZ_SWEEP runs the islanding test over a grid of reactive power mismatch
%   (dQ) and load quality factor (Qf), recording whether SFS detects the
%   island within the criterion and how long it takes.
%
%   NDZ_SWEEP(QFROWS) runs only the Qf rows given by the index vector
%   QFROWS, appending to any results already stored. Use this to run the
%   sweep in chunks: a point where detection FAILS runs the full stop time
%   and is roughly ten times slower than one that trips early, so a full
%   sweep in one call can take the best part of an hour.
%
%   Axes. dP is deliberately not swept. The load's phase angle depends only
%   on Qf and the ratio f/f_res, so dP moves the resistance and therefore
%   the voltage, but leaves the resonant frequency and the phase slope
%   untouched - it cannot affect frequency-based detection. Qf is the sole
%   load parameter in the detection condition kSFS > 4*Qf/(pi*f_n), which
%   predicts failure above
%
%       Qf_crit = kSFS*pi*f_n/4 = 1.96   for kSFS = 0.05
%
%   so the Qf range brackets that prediction.
%
%   Results are saved to results/ndz_sweep.mat. Plot with NDZ_PLOT.
%
%   Usage:
%       ndz_sweep          % everything (slow - prefer chunks)
%       ndz_sweep(1:2)     % first two Qf rows
%
%   See also RLCTESTLOAD, NDZ_PLOT, PROTECTIONPARAMS

mdl  = 'SFS';
here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(here));
addpath(here);
outdir = fullfile(root,'results');
if ~isfolder(outdir), mkdir(outdir); end
matfile = fullfile(outdir,'ndz_sweep.mat');

pp = protectionParams();
assignin('base','pp',pp);
if ~bdIsLoaded(mdl), load_system(fullfile(here,[mdl '.slx'])); end

% --- the grid ---------------------------------------------------------
dQ_grid = linspace(-0.5, 0.5, 11);
Qf_grid = [0.5 1.0 1.5 2.0 2.5 3.0 3.5];
if nargin < 1 || isempty(qfRows), qfRows = 1:numel(Qf_grid); end

% --- load or initialise the results store -----------------------------
if isfile(matfile)
    S = load(matfile);
    if ~isequal(S.dQ_grid, dQ_grid) || ~isequal(S.Qf_grid, Qf_grid)
        error('ndz_sweep:gridChanged', ...
            'Stored results use a different grid. Delete %s first.', matfile);
    end
else
    S.dQ_grid = dQ_grid;
    S.Qf_grid = Qf_grid;
    S.t_det   = nan(numel(Qf_grid), numel(dQ_grid));   % detection time, NaN = no trip
    S.done    = false(numel(Qf_grid), numel(dQ_grid));
    S.Qf_crit = pp.kSFS*pi*pp.f_n/4;
end

% --- make sure the trip signal is logged -------------------------------
ph = get_param([mdl '/TripLogic'],'PortHandles');
set_param(ph.Outport(1), 'DataLogging','on', ...
    'DataLoggingNameMode','Custom', 'DataLoggingName','trip');
set_param(mdl,'SignalLogging','on','SignalLoggingName','logsout');

rBlk = [mdl '/RLC_Load/R_load'];
lBlk = [mdl '/RLC_Load/L_load'];
cBlk = [mdl '/RLC_Load/C_load'];

fprintf('Qf_crit predicted = %.3f  (kSFS = %.4f)\n\n', S.Qf_crit, pp.kSFS);

for jj = qfRows(:).'
    qf = Qf_grid(jj);
    fprintf('--- Qf = %.2f  (%s predicted) ---\n', qf, ...
        string(qf < S.Qf_crit) + " detect");
    for ii = 1:numel(dQ_grid)
        dq = dQ_grid(ii);

        % load for this point, at this quality factor
        ppi = pp;  ppi.Qf = qf;
        [R, L, C_tot] = rlcTestLoad(0, dq, ppi);

        % the filter capacitor is part of what the island sees, so the bank
        % carries the remainder
        C_bank = C_tot - pp.Cf;

        % start the inductor in steady state, or the startup DC offset
        % returns at every off-nominal L
        iL0 = -pp.Vg_amp/(pp.w_n*L);

        in = Simulink.SimulationInput(mdl);
        in = in.setBlockParameter( ...
            rBlk, 'R',   sprintf('%.12g', R), ...
            lBlk, 'l',   sprintf('%.12g', L), ...
            lBlk, 'i_L', sprintf('%.12g', iL0), ...
            lBlk, 'i_L_specify', 'on', ...
            cBlk, 'c',   sprintf('%.12g', C_bank));

        t0 = tic;
        out = sim(in);
        tr = out.logsout.get('trip');
        k  = find(double(tr.Values.Data) > 0.5, 1);

        if isempty(k)
            det = NaN;
            verdict = 'NO TRIP';
        else
            det = tr.Values.Time(k) - pp.t_island;
            if det > pp.t_trip_max
                verdict = sprintf('%.3f s  TOO SLOW', det);
                det = NaN;                    % outside the criterion = not detected
            else
                verdict = sprintf('%.3f s', det);
            end
        end

        S.t_det(jj,ii) = det;
        S.done(jj,ii)  = true;
        fprintf('   dQ = %+5.2f : %-16s (%.0f s)\n', dq, verdict, toc(t0));

        save(matfile, '-struct', 'S');   % checkpoint every point
    end
    fprintf('\n');
end

n = nnz(S.done);
fprintf('%d of %d points complete. Results in %s\n', ...
    n, numel(S.done), matfile);
if n == numel(S.done)
    fprintf('Sweep finished - run ndz_plot to draw it.\n');
end
end
