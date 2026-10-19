function files = plotFault(names, opts)
%PLOTFAULT  One figure per grid-fault run (ride-through), PNG into results/figures.
%
%   files = plotFault()                                  "grid_dip"
%   files = plotFault([], Model="intSystem_aqibPLL")     runs saved by runIntegration(..., Model=)
%
% Five panels around the fault (shaded): PCC voltage, grid current, the PLL's
% frequency estimate against the 47-52 Hz trip band, the DC bus against the
% 5 % band and the 800 V ride-through limit, and the trip line.

arguments
    names = []
    opts.Model (1,1) string = "intSystem"
end
if isempty(names), names = "grid_dip"; end
P = intPaths();
% same rule as runIntegration: any model other than the reference saves to results/<model>/
if opts.Model ~= "intSystem", P.results = fullfile(P.results, opts.Model); end
figDir = fullfile(P.results, 'figures');
if ~isfolder(figDir), mkdir(figDir); end
xp = intParams();  files = strings(0);

for nm = string(names)
    if ~isfile(fullfile(P.results, nm + ".mat")), continue; end
    S = load(fullfile(P.results, nm + ".mat"));
    L = S.logsout;  s = S.s;  r = S.r;  fr = r.frt;
    g = @(n) L.get(n).Values;
    t0 = fr.t_fault;  tc = fr.t_clear;  xl = [t0 - 0.1, s.T];

    tl = g('inv_tlm');
    V = rows(tl.v_abc);  I = rows(tl.i2_abc);
    vdc = g('v_dc');  tr = g('trip');  wh = g('w_hat');

    f = figure('Visible','off', 'Color','w', 'Position',[100 100 900 900]);
    tiledlayout(f, 5, 1, 'TileSpacing','compact', 'Padding','compact');
    nexttile; plot(tl.v_abc.Time, V); ylabel('v_{PCC} [V]'); ylim([-500 500]); shade(t0, tc); xlim(xl); grid on
    title(sprintf('PCC voltage: %.2f pu left during the %.0f ms fault', fr.Vpcc_fault_pu, 1e3*(tc - t0)));
    nexttile; plot(tl.i2_abc.Time, I); ylabel('i_{grid} [A]'); shade(t0, tc); xlim(xl); grid on
    title(sprintf('Grid current: %.0f A peak (%.1f pu) around clearing', fr.i_pk_A, fr.i_pk_pu));
    nexttile; plot(wh.Time, wh.Data(:)/(2*pi)); yline([xp.prot.f_min xp.prot.f_max], 'r--');
    ylabel('PLL f [Hz]'); shade(t0, tc); xlim(xl); ylim([40 60]); grid on
    nexttile; plot(vdc.Time, vdc.Data(:), 'k'); hold on
    yline(xp.Vdc_ref*[0.95 1.05], 'r--');  yline(xp.frt.Vdc_max, 'r-', '800 V ride-through limit');
    ylim([650 xp.frt.Vdc_max + 25]); ylabel('v_{dc} [V]'); shade(t0, tc); xlim(xl); grid on
    title(sprintf('DC bus: peak %.0f V, back in \\pm1 %% %.0f ms after clearing; power back %.2f s after', ...
        fr.Vdc_peak, fr.vdc_back_ms, fr.P_back_s));
    nexttile; stairs(tr.Time, tr.Data(:)); ylabel('trip'); ylim([-0.1 1.1]); shade(t0, tc); xlim(xl); grid on
    xlabel('t [s]')
    sgtitle(f, strjoin(textwrap(s.name + "  -  " + s.why, 120), newline), 'Interpreter','none', 'FontSize', 10);
    fn = fullfile(figDir, nm + ".png");
    exportgraphics(f, fn, 'Resolution', 130);
    close(f);
    files(end+1) = fn; %#ok<AGROW>
end
end

function shade(a, b)
yl = ylim; hold on
patch([a b b a], [yl(1) yl(1) yl(2) yl(2)], [1 0.85 0.85], 'EdgeColor','none', 'FaceAlpha',0.4, 'HandleVisibility','off');
ylim(yl); hold off
end

function x = rows(ts)
x = squeeze(ts.Data);
if size(x,1) ~= numel(ts.Time), x = x.'; end
end
