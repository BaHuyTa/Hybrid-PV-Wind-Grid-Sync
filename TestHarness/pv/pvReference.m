function ref = pvReference(G, P, opts)
%PVREFERENCE The most power this converter could possibly deliver, found without the MPPT.
%
%   ref = pvReference(1000)                  cached if already computed
%   ref = pvReference(1000, P, Force = true) recompute
%
%   Tracking efficiency is a ratio, and the denominator cannot come from the
%   algorithm being tested. This sweeps duty cycle across its full range with
%   the P&O block removed (pvSweep.slx) and reports the best steady-state panel
%   power the hardware can reach. Coarse pass, then a fine pass around the
%   winner, because the peak is flat and a coarse grid alone reads low.
%
%   Fields:
%     Pmax        best steady-state panel power                          [W]
%     Dmpp        duty that achieved it                                  [-]
%     Vpv, Ipv    panel operating point there                            [V, A]
%     Vbus        DC bus voltage there                                   [V]
%     reachable   false when Dmpp landed on a duty rail
%     Dgrid, Pgrid   the whole sweep, for plotting
%
%   WHAT "reachable = false" MEANS, AND WHY IT IS REPORTED SEPARATELY.
%   A boost converter presents its source with R_in = R_load * (1-D)^2. The
%   panel's own maximum-power resistance is Vmpp/Impp, and it RISES as
%   irradiance falls, because Vmpp barely moves while Impp scales with the sun.
%   So low irradiance needs a HIGH R_in, which needs a LOW duty -- and duty
%   stops at Dmin. Below some irradiance the operating point the panel wants is
%   simply outside what the converter can present, and no MPPT algorithm can fix
%   that. When that happens the sweep's own maximum sits on the rail, and
%   tracking efficiency measured against it becomes meaningless: a saturated
%   controller scores 100 % against a saturated ceiling. Hence this flag.

arguments
    G          (1,1) double
    P          struct  = pvParams()
    opts.Force (1,1) logical = false
    opts.Quiet (1,1) logical = false
    opts.T     (1,1) double  = 25       % cell temperature [C]
end

here     = fileparts(mfilename("fullpath"));
cacheDir = fullfile(here, "results", "reference");
if ~isfolder(cacheDir); mkdir(cacheDir); end
% Temperature is in the name because the peak moves with it: 348 V at 25 C,
% 290 V at 65 C. A cache keyed on irradiance alone would hand a hot run the
% 25 C ceiling and score it against a peak it can never reach.
cacheFile = fullfile(cacheDir, sprintf("mpp_%04d_T%02d.mat", round(G), round(opts.T)));

if ~opts.Force && isfile(cacheFile)
    S = load(cacheFile, "ref");
    ref = S.ref;
    return
end

buildPVModels();
mdl = P.uut.sweepModel;
if ~bdIsLoaded(mdl)
    load_system(fullfile(fileparts(here), "models", mdl + ".slx"));
end

% Coarse, then fine around the winner.
[Pc, Vc, Ic, Bc] = sweepDuty(P.sweep.Dgrid, G, opts.T, P, mdl);
[~, iBest]  = max(Pc);
lo = max(P.ctrl.Dmin, P.sweep.Dgrid(iBest) - 0.05);
hi = min(P.ctrl.Dmax, P.sweep.Dgrid(iBest) + 0.05);
Dfine = lo:P.sweep.refineDD:hi;
[Pf, Vf, If, Bf] = sweepDuty(Dfine, G, opts.T, P, mdl);

D = [P.sweep.Dgrid, Dfine];
Pp = [Pc, Pf]; Vv = [Vc, Vf]; Ii = [Ic, If]; Bb = [Bc, Bf];
[D, ord] = sort(D);
Pp = Pp(ord); Vv = Vv(ord); Ii = Ii(ord); Bb = Bb(ord);

[ref.Pmax, iM] = max(Pp);
ref.Dmpp  = D(iM);
ref.Vpv   = Vv(iM);
ref.Ipv   = Ii(iM);
ref.Vbus  = Bb(iM);
ref.Dgrid = D;
ref.Pgrid = Pp;
ref.Vgrid = Vv;
ref.Bgrid = Bb;
ref.G     = G;
ref.T     = opts.T;

% On the rail, within one refinement step.
ref.reachable = ref.Dmpp > P.ctrl.Dmin + P.sweep.refineDD && ...
                ref.Dmpp < P.ctrl.Dmax - P.sweep.refineDD;

save(cacheFile, "ref");
if ~opts.Quiet
    rail = "";
    if ~ref.reachable
        rail = "   <- ON THE DUTY RAIL: the panel optimum is out of reach";
    end
    fprintf("  reference @ %4d W/m^2, %2d C : Pmax %7.1f W at %5.1f V, D = %.3f%s" + newline, ...
            G, round(opts.T), ref.Pmax, ref.Vpv, ref.Dmpp, rail);
end
end

% -----------------------------------------------------------------------------
function [Pavg, Vavg, Iavg, Bavg] = sweepDuty(Dgrid, G, T, P, mdl)
%SWEEPDUTY Steady-state operating point at each fixed duty.
%   Runs the points in parallel when a pool is already open, serially when not.
%   The harness never opens a pool itself: that is the caller's decision, and a
%   test suite that silently spins up workers is a test suite nobody can run on
%   a laptop.
irr  = timeseries([G; G], [0; P.sweep.stopTime]);
n    = numel(Dgrid);
Pavg = nan(1, n); Vavg = Pavg; Iavg = Pavg; Bavg = Pavg;

si = repmat(Simulink.SimulationInput(mdl), 1, n);
for k = 1:n
    si(k) = Simulink.SimulationInput(mdl);
    si(k) = si(k).setModelParameter(StopTime = num2str(P.sweep.stopTime));
    si(k) = si(k).setVariable("irrProfile", irr);
    si(k) = si(k).setVariable("D_fix", Dgrid(k));
    si(k) = si(k).setBlockParameter(mdl + "/Solar Panel", "CellTempC", num2str(T));
    si(k) = pvBusInput(si(k), P, P.sweep.stopTime);
end
outs = pvRunMany(si);

for k = 1:n
    o = outs(k);
    L = o.logsout;
    V = L.getElement("V").Values;
    I = L.getElement("I").Values;
    B = L.getElement("Vdc").Values;

    % Average over the tail only. The first samples are the Simscape start-up
    % transient, and averaging those in would drag every point low by a
    % different amount, tilting the whole curve and moving the reported peak.
    %
    % Time-weighted, not mean(): the solver crowds its steps around switching
    % edges, so a plain mean over-weights those instants. Measured at 1000 W/m^2
    % the difference is under 0.001 %, but this is the same time average the
    % energy-based IEC metric divides by, and the two should not differ in kind.
    m  = V.Time > (P.sweep.stopTime - P.sweep.avgWindow);
    tw = V.Time(m);
    avg = @(x) trapz(tw, x) / (tw(end) - tw(1));
    Vavg(k) = avg(V.Data(m));
    Iavg(k) = avg(I.Data(m));
    Pavg(k) = avg(V.Data(m) .* I.Data(m));
    Bavg(k) = avg(interp1(B.Time, B.Data, tw));
end
end
