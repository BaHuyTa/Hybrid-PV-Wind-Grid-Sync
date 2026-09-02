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
end

here     = fileparts(mfilename("fullpath"));
cacheDir = fullfile(here, "results", "reference");
if ~isfolder(cacheDir); mkdir(cacheDir); end
cacheFile = fullfile(cacheDir, sprintf("mpp_%04d.mat", round(G)));

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
[Pc, Vc, Ic, Bc] = sweepDuty(P.sweep.Dgrid, G, P, mdl);
[~, iBest]  = max(Pc);
lo = max(P.ctrl.Dmin, P.sweep.Dgrid(iBest) - 0.05);
hi = min(P.ctrl.Dmax, P.sweep.Dgrid(iBest) + 0.05);
Dfine = lo:P.sweep.refineDD:hi;
[Pf, Vf, If, Bf] = sweepDuty(Dfine, G, P, mdl);

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

% On the rail, within one refinement step.
ref.reachable = ref.Dmpp > P.ctrl.Dmin + P.sweep.refineDD && ...
                ref.Dmpp < P.ctrl.Dmax - P.sweep.refineDD;

save(cacheFile, "ref");
if ~opts.Quiet
    rail = "";
    if ~ref.reachable
        rail = "   <- ON THE DUTY RAIL: the panel optimum is out of reach";
    end
    fprintf("  reference @ %4d W/m^2 : Pmax %7.1f W at D = %.3f%s" + newline, ...
            G, ref.Pmax, ref.Dmpp, rail);
end
end

% -----------------------------------------------------------------------------
function [Pavg, Vavg, Iavg, Bavg] = sweepDuty(Dgrid, G, P, mdl)
%SWEEPDUTY Steady-state operating point at each fixed duty.
irr  = timeseries([G; G], [0; P.sweep.stopTime]);
n    = numel(Dgrid);
Pavg = nan(1, n); Vavg = Pavg; Iavg = Pavg; Bavg = Pavg;

for k = 1:n
    si = Simulink.SimulationInput(mdl);
    si = si.setModelParameter(StopTime = num2str(P.sweep.stopTime));
    si = si.setVariable("irrProfile", irr);
    si = si.setVariable("D_fix", Dgrid(k));
    o  = sim(si);

    L = o.logsout;
    V = L.getElement("V").Values;
    I = L.getElement("I").Values;
    B = L.getElement("Vdc").Values;

    % Average over the tail only. The first samples are the Simscape start-up
    % transient, and averaging those in would drag every point low by a
    % different amount, tilting the whole curve and moving the reported peak.
    m = V.Time > (P.sweep.stopTime - P.sweep.avgWindow);
    Vavg(k) = mean(V.Data(m));
    Iavg(k) = mean(I.Data(m));
    Pavg(k) = mean(V.Data(m) .* I.Data(m));
    Bavg(k) = mean(B.Data(m));
end
end
