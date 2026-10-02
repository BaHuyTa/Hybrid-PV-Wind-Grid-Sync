function ndz_plot()
%NDZ_PLOT Draw the non-detection zone from the stored sweep results.
%   Reads results/ndz_sweep.mat and plots detection time against reactive
%   power mismatch and load quality factor, marking the points where SFS
%   failed to detect the island within the criterion and the quality factor
%   at which theory predicts that failure.
%
%   Colours are set explicitly and the figure is built invisible, so the
%   output does not depend on the MATLAB desktop theme. Do not add a call to
%   theme() here - it can block the session when driven non-interactively.
%
%   Usage:
%       ndz_plot
%
%   See also NDZ_SWEEP

here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(here));
outdir = fullfile(root,'results');
matfile = fullfile(outdir,'ndz_sweep.mat');
assert(isfile(matfile), 'No sweep results at %s. Run ndz_sweep first.', matfile);
S = load(matfile);

if ~all(S.done(:))
    warning('ndz_plot:incomplete', '%d of %d points not yet run.', ...
        nnz(~S.done), numel(S.done));
end

detected = ~isnan(S.t_det);

% --- figure ------------------------------------------------------------
fg = figure('Color','w','Position',[100 100 980 520],'Visible','off', ...
            'InvertHardcopy','off');
ax = axes(fg); hold(ax,'on'); box(ax,'on');
set(ax,'Color',[0.93 0.93 0.93],'XColor','k','YColor','k', ...
       'FontSize',11,'LineWidth',1.0,'Layer','top');

% detection time as colour; failures left as the grey background
im = imagesc(ax, S.dQ_grid, S.Qf_grid, S.t_det*1000);
set(im,'AlphaData', detected);
set(ax,'YDir','normal');
colormap(ax, parula);
cb = colorbar(ax);
cb.Label.String = 'detection time (ms)';
cb.Label.FontSize = 11;
cb.Color = 'k';

% mark the failures explicitly
[jj,ii] = find(~detected);
if ~isempty(jj)
    plot(ax, S.dQ_grid(ii), S.Qf_grid(jj), 'x', 'MarkerSize',12, ...
        'LineWidth',2.2, 'Color',[0.75 0 0]);
end

% The analytical threshold is where RUNAWAY begins, not where detection
% fails: above it the frequency still travels toward an equilibrium, and is
% detected whenever that journey crosses a trip threshold in time.
yline(ax, S.Qf_crit, '--', ...
    sprintf('Q_f = %.2f  runaway threshold (not the detection limit)', S.Qf_crit), ...
    'Color',[0.75 0 0], 'LineWidth',2.0, 'FontSize',10.5, ...
    'LabelHorizontalAlignment','left', 'LabelVerticalAlignment','bottom');

% measured boundary: highest Qf detected at every dQ
qfOK = S.Qf_grid(find(all(detected,2),1,'last'));
if ~isempty(qfOK)
    yline(ax, qfOK, '-', sprintf('Q_f = %.1f  measured: detected at every \\DeltaQ', qfOK), ...
        'Color',[0 0.45 0], 'LineWidth',2.0, 'FontSize',10.5, ...
        'LabelHorizontalAlignment','right', 'LabelVerticalAlignment','top');
end

xlabel(ax, 'Reactive power mismatch  \DeltaQ  (per unit of P_{inv})', ...
    'Color','k','FontSize',12);
ylabel(ax, 'Load quality factor  Q_f', 'Color','k','FontSize',12);

nFail = nnz(~detected);
if nFail == 0
    sub = 'SFS detected every case - no non-detection zone in the swept range';
else
    sub = sprintf('%d of %d cases not detected within %g s (red crosses)', ...
        nFail, numel(detected), 2);
end
title(ax, {'Non-detection zone: detection time vs load detuning and quality factor', sub}, ...
    'Color','k','FontSize',12.5,'FontWeight','bold');

exportgraphics(fg, fullfile(outdir,'fig6_ndz_sweep.png'), ...
    'Resolution',200,'BackgroundColor','white');
close(fg);

% --- summary -----------------------------------------------------------
fprintf('\n=== NDZ SWEEP SUMMARY ===\n');
fprintf('predicted critical Qf : %.3f\n', S.Qf_crit);
allDet = all(detected,2);
anyDet = any(detected,2);
hiOK = S.Qf_grid(find(allDet,1,'last'));
loNo = S.Qf_grid(find(~anyDet,1,'first'));
if ~isempty(hiOK), fprintf('detected at every dQ up to Qf = %.2f\n', hiOK); end
if ~isempty(loNo), fprintf('detected at no dQ from   Qf = %.2f\n', loNo); end
fprintf('cases not detected    : %d of %d\n', nFail, numel(detected));
if any(detected(:))
    fprintf('detection time range  : %.1f to %.1f ms\n', ...
        1000*min(S.t_det(detected)), 1000*max(S.t_det(detected)));
end
fprintf('written: %s\n', fullfile(outdir,'fig6_ndz_sweep.png'));
end
