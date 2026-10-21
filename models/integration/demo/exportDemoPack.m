function pack = exportDemoPack(opts)
%EXPORTDEMOPACK  Shrink the saved integration runs into one small file for LiveDemo.
%
%   exportDemoPack()                    results/intSystem_aqibPLL/*.mat -> demo/demoPack.mat
%   exportDemoPack(Model="myModel")
%
% LiveDemo never simulates: it replays these runs. Each run's logs (~30-200 MB)
% become a few MB: the slow signals (power, DC bus, PLL f, trip) binned to a display
% rate, and the PCC voltage and grid current, all three phases, at 10 kHz for the
% scope. Bin means, not sample picks, so the switching ripple averages out instead
% of aliasing. Make the runs first (about 1.5 h on 3-5 workers):
%
%   runIntegration(["day_load_min","day_load_mid","day_load_max","grid_dip","island_sfs","demo"], ...
%                  Model="intSystem_aqibPLL", Parallel=true);

arguments
    opts.Model (1,1) string = "intSystem_aqibPLL"
    opts.Out   (1,1) string = ""
end
here = fileparts(mfilename('fullpath'));
addpath(fileparts(here));                          % models/integration
P  = intPaths();
rd = P.results;  if opts.Model ~= "intSystem", rd = fullfile(rd, opts.Model); end
if opts.Out == "", opts.Out = fullfile(here, "demoPack.mat"); end
xp = intParams();  dp = gullenProfile();

%       run             kind       load kW  SFS
list = {"day_load_min", "day",      50, true
        "day_load_mid", "day",     150, true
        "day_load_max", "day",     250, true
        "grid_dip_50",  "dip",      50, true
        "grid_dip_150", "dip",     150, true
        "grid_dip",     "dip",     250, true
        "shed_50",      "shed",     50, true
        "shed_150",     "shed",    150, true
        "shed_250",     "shed",    250, true
        "island_sfs",   "island",  NaN, true
        "island_nosfs", "island",  NaN, false};

pack.model   = opts.Model;
pack.made    = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm'));
pack.lim     = struct('Vdc_ref', xp.Vdc_ref, 'band', 0.05, 'Vdc_max', xp.frt.Vdc_max, ...
                      'f_min', xp.prot.f_min, 'f_max', xp.prot.f_max, 't_pickup', xp.prot.t_pickup, ...
                      't_island_max', 2.0, 'S_rated', 150);
pack.day     = struct('clock0', dp.t_real(1), 'step', dp.step, 'compression', dp.compression);
pack.runs    = struct([]);
missing = strings(0);

for k = 1:size(list, 1)
    nm = list{k,1};  f = fullfile(rd, nm + ".mat");
    if ~isfile(f), missing(end+1) = nm; continue; end %#ok<AGROW>
    fprintf('%-13s ', nm);  t0 = tic;
    S = load(f, 'logsout', 'r');  L = S.logsout;  r = S.r;
    s = intScenarios(nm);                          % weather handles + overrides, from source
    xs = xp;
    for j = 1:2:numel(s.set), q = strsplit(char(s.set{j}), '.'); xs = setfield(xs, q{:}, s.set{j+1}); end %#ok<SFLD>
    g = @(n) L.get(n).Values;
    names = string(L.getElementNames);

    u = struct('name', nm, 'kind', list{k,2}, 'load', list{k,3}, 'sfs', list{k,4}, ...
               'why', s.why, 'T', s.T);
    isDay = u.kind == "day";
    % Slow grid: one point per 1/200 s of the day (= 6 s of real day), 0.5 ms for events.
    fsS = tern(isDay, 200, 2000);   fsF = 10e3;
    tA  = tern(isDay, 0, 0.3);                     % events: skip start-up
    u.tS = single((tA : 1/fsS : s.T)');
    u.tF = single((tA : 1/fsF : s.T)');

    % Power from the energy meters [pv wind invdc ac], d/dt then a moving mean:
    % one 5-min weather sample on the day, 5 ms (a quarter cycle) in an event.
    E  = g('E');  Ed = rows(E);  te = E.Time;  dte = median(diff(te));
    nP = round(tern(isDay, dp.step, 5e-3)/dte);
    Pw = movmean(gradient(Ed.', dte).', nP) / 1e3;
    Pk = binMean(te, Pw, u.tS);
    u.Ppv = Pk(:,1);  u.Pwind = Pk(:,2);  u.Pac = Pk(:,4);

    % Local load: the constant-PQ site load on its breaker, the RLC test load on its.
    tS = double(u.tS);
    site = xs.pcc.site.P/1e3 * (~xs.pcc.site.open0 & tS < xs.pcc.site.t);
    rlc  = xs.pcc.rlc.P/1e3  * (~xs.pcc.rlc.open0  & tS < xs.pcc.rlc.t);
    u.Pload = single(site + rlc);
    u.load_label = tern(rlc(1) > 0, "Local test load (matched)", "Site load");
    u.grid_on = single(~xs.pcc.grid.open0 & tS < xs.pcc.grid.t);
    u.Pgrid = single((site + rlc - double(u.Pac)) .* double(u.grid_on));   % + = import

    v = g('v_dc');   u.vdc = binMean(v.Time, v.Data(:), u.tS);
    w = g('w_hat');  u.f   = binMean(w.Time, w.Data(:)/(2*pi), u.tS);
    if any(names == "trip"), tr = g('trip');  u.trip = binMax(tr.Time, tr.Data(:), u.tS);
    else,                    u.trip = zeros(size(u.tS), 'single');
    end
    u.G  = single(s.G(tS));  u.vw = single(s.v_wind(tS));

    tl = g('inv_tlm');
    u.vabc = binMean(tl.v_abc.Time,  rows(tl.v_abc),  u.tF);
    u.iabc = binMean(tl.i2_abc.Time, rows(tl.i2_abc), u.tF);

    % Events, and what the verdict card says (all measured, nothing typed in).
    u.t_event = NaN;  u.t_clear = NaN;  u.v = struct();
    fr = w.Data(:)/(2*pi);  tw = w.Time;
    switch u.kind
        case "dip"
            u.t_event = xs.flt.t;  u.t_clear = xs.flt.t + xs.flt.dur;
            u.v = r.frt;
        case "shed"
            u.t_event = xs.pcc.site.t;
            u.v.Vdc_peak = max(v.Data(v.Time >= u.t_event));
            u.v.tripped  = any(u.trip > 0.5);
        case "island"
            u.t_event = xs.pcc.grid.t;
            u.v = r.prot;
            u.v.tripped = isfinite(r.t_trip) && r.t_trip < s.T;
    end
    if isfinite(u.t_event)
        % Longest stretch of the PLL frequency outside 47-52 Hz after the event:
        % the relay trips once it has been out for t_pickup (50 ms).
        u.v.oob_ms = 1e3*longestRun(tw(tw >= u.t_event), ...
            fr(tw >= u.t_event) < xp.prot.f_min | fr(tw >= u.t_event) > xp.prot.f_max);
        u.v.f_range = [min(fr(tw >= u.t_event)) max(fr(tw >= u.t_event))];
        ko = find(tw >= u.t_event & (fr < xp.prot.f_min | fr > xp.prot.f_max), 1);   % first out of band
        u.v.t_out_ms = NaN;  if ~isempty(ko), u.v.t_out_ms = 1e3*(tw(ko) - u.t_event); end
    end
    u.t_trip = r.t_trip;
    u.r = rmfield(r, intersect(fieldnames(r), {'h'}));
    pack.runs = [pack.runs u];
    fprintf('%.0f s\n', toc(t0));
end

if ~isempty(missing)
    warning('exportDemoPack:missing', 'Not found in %s (LiveDemo greys these out): %s', rd, strjoin(missing, ', '));
end
save(opts.Out, 'pack');
d = dir(opts.Out);
fprintf('%s: %d runs, %.1f MB\n', opts.Out, numel(pack.runs), d.bytes/1e6);
end

function y = binMean(t, x, tg)
% Mean of the samples x (N x k, at times t) in each bin centred on the uniform grid tg.
% Bins with no sample (a signal logged slower than the grid) take the previous value.
t  = double(t(:));  tg = double(tg);  dt = tg(2) - tg(1);
k  = round((t - tg(1))/dt) + 1;  ok = k >= 1 & k <= numel(tg);
n  = accumarray(k(ok), 1, [numel(tg) 1]);
y  = zeros(numel(tg), size(x, 2), 'single');
for c = 1:size(x, 2)
    y(:,c) = single(accumarray(k(ok), double(x(ok,c)), [numel(tg) 1]) ./ n);
end
y = fillmissing(fillmissing(y, 'previous'), 'next');
end

function y = binMax(t, x, tg)
t  = double(t(:));  tg = double(tg);  dt = tg(2) - tg(1);
k  = round((t - tg(1))/dt) + 1;  ok = k >= 1 & k <= numel(tg);
y  = single(accumarray(k(ok), double(x(ok)), [numel(tg) 1], @max, NaN));
y  = fillmissing(fillmissing(y, 'previous'), 'next');
end

function d = longestRun(t, m)
% Longest time m stays true.
d = 0;  if ~any(m), return; end
e = diff([0; m(:); 0]);  a = find(e == 1);  b = find(e == -1) - 1;
d = max(t(min(b + 1, numel(t))) - t(a));
end

function x = rows(ts)
x = squeeze(ts.Data);
if size(x,1) ~= numel(ts.Time), x = x.'; end
end

function v = tern(c, a, b), if c, v = a; else, v = b; end, end
