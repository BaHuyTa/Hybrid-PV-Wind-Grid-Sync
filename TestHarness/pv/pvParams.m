function P = pvParams(variant)
%PVPARAMS Single source of truth for testing the PV boost + MPPT stage.
%
%   P = pvParams()              nominal.
%   P = pvParams("slowPO")      P&O perturbation step halved, to prove the
%                               reacquisition metric actually moves.
%
%   THE SPEC IN THIS FILE WAS WRITTEN BEFORE MEASURING BELAL'S MODEL.
%   That ordering is the whole point. A limit chosen after looking at what the
%   model happens to do is not a requirement, it is a description -- and it will
%   pass forever, including on the day the model breaks. Every number below is
%   justified from the system the stage has to live in, not from a run.
%
%   Fields:
%     P.uut     which model is under test and where its source lives
%     P.sweep   settings for the independent maximum-power reference
%     P.spec    the pass/fail contract

arguments
    variant (1,1) string = "nominal"
end

%% Unit under test
% Belal's file is READ ONLY as far as this harness is concerned. buildPVModels
% copies it and instruments the copy. Editing a teammate's model in place is how
% you end up unable to answer "did my change break it, or was it already broken?"
P.uut.sourceModel = fullfile("..", "..", "Belal's PV", "solarsimulink.slx");
P.uut.sweepModel  = "pvSweep";   % same plant, MPPT replaced by a fixed duty

%% Maximum-power reference
% Tracking efficiency needs a denominator, and it has to come from somewhere
% other than the algorithm being tested. This sweeps duty cycle across the full
% range with the MPPT removed, and takes the best steady-state power the
% converter can actually produce into its load. That is the honest ceiling: not
% the panel datasheet number, but the most this hardware could deliver if the
% controller were perfect.
P.sweep.Dgrid     = 0.05:0.05:0.95;   % coarse pass
P.sweep.refineDD  = 0.005;            % then refine around the winner
P.sweep.stopTime  = 0.08;             % output RC is 9.8 ms; 8 tau is settled
P.sweep.avgWindow = 0.02;             % average the last 20 ms

%% Controller knobs -- the variant axis
% P&O perturbs duty by dD every Ts. That product is a SLEW RATE, and it caps how
% fast the stage can chase a cloud edge regardless of how good everything else
% is. As delivered: 0.002 per 10 ms = 0.2 duty per second.
%
% The variant exists to answer the question a bug report cannot: is the
% delivered value the cause, and does raising it actually fix the problem?
% "fastPO" is a candidate fix, not a fault injection -- five times the slew
% rate. It is expected to trade against steady-state ripple, because a larger
% perturbation is a larger dither around the peak. Surfacing that trade rather
% than hiding it is the point: a harness that can say "this fixes A and costs B"
% has given someone a decision they can actually make.
switch variant
    case "nominal"
        P.ctrl.dD = 0.002;   % as delivered
    case "fastPO"
        P.ctrl.dD = 0.010;   % candidate fix: 5x the slew rate
    otherwise
        error("pvParams:badVariant", ...
              "variant must be ""nominal"" or ""fastPO"", got ""%s"".", variant);
end
P.ctrl.Ts       = 0.010;   % P&O sample time, read from the function block
P.ctrl.trendPeriods = 10;  % perturbations to average over when asking whether
                           % the stage has MOVED, as opposed to how much it
                           % dithers. See evaluatePVSpec for why one filter
                           % cannot answer both questions.
P.ctrl.variant  = variant;
P.ctrl.Dmin     = 0.05;    % hard-coded inside the P&O function block
P.ctrl.Dmax     = 0.95;
P.ctrl.slewRate = P.ctrl.dD / P.ctrl.Ts;   % [duty/s]

% dD is a literal inside the MATLAB Function block, not a tunable parameter, so
% a variant cannot be injected at run time the way the DC-link harness injects
% its P struct. Each variant therefore gets its own generated model, and
% buildPVModels patches the literal in the copy. The original stays untouched.
if variant == "nominal"
    P.uut.model = "pvUUT";
else
    P.uut.model = "pvUUT_" + variant;
end

%% Specification
% --- 1. Tracking efficiency -------------------------------------------------
% An MPPT that captures less than ~98 % of available power is not earning the
% converter losses it costs. 98 % is the ordinary commercial figure quoted for
% P&O; EN 50530 static efficiency tests are run against the same order of number.
P.spec.trackingEffPct = 98;

% --- 2. Reacquisition after an irradiance change ----------------------------
% A cloud edge crossing the array is a step in all but name. Half a second to
% get back inside the tracking band is generous for a 10 ms perturbation period
% -- it allows 50 perturbations, i.e. 0.1 of duty travel at the delivered slew
% rate. If the stage cannot do it in that, the limit is structural, not tuning.
P.spec.reacquireTime  = 0.5;    % [s]

% --- 3. Duty must not sit on a rail -----------------------------------------
% Steady-state duty parked at Dmin or Dmax does not mean the controller is
% happy. It means the operating point it wants is OUTSIDE what this converter
% and load can reach, and the panel is being held off its maximum by the
% hardware. Tracking efficiency alone cannot see this: measured against a
% ceiling that is itself rail-limited, a saturated controller scores 100 %.
% These two checks together separate "the algorithm is bad" from "the algorithm
% is fine but it has been given an impossible operating point".
P.spec.dutyRailMargin = 0.02;   % [-] required clearance from both rails

% --- 4. Steady-state power ripple -------------------------------------------
% P&O never settles; it dithers around the peak by construction. The spec bounds
% the dither rather than pretending it is absent. 2 % peak-to-peak is the usual
% design target -- above that the loss from dithering starts to eat the gain
% from tracking.
P.spec.powerRipplePct = 2;      % [%] peak-to-peak, of mean power

% --- 5. The DC-link interface -----------------------------------------------
% THIS IS THE REQUIREMENT THAT MATTERS FOR INTEGRATION, and it comes from the
% other side of the boundary: config/harnessParams.m regulates the shared bus to
% 700 V and holds it inside +/-1 %. Anything feeding that bus has to arrive at
% the same voltage. +/-5 % is the wider envelope the PV stage is allowed during
% transients, on the argument that the grid-side loop absorbs the rest.
%
% Written down here, in the PV stage's own spec, precisely because a number that
% lives only in someone else's file is a number nobody checks. See DESIGN_NOTES
% section 11: mismatched interface assumptions blow up integration week far more
% often than control theory does.
P.spec.busNom    = 700;         % [V] shared DC-link setpoint
P.spec.busTolPct = 5;           % [%] envelope for the PV stage
P.spec.busMin    = (1 - P.spec.busTolPct/100) * P.spec.busNom;
P.spec.busMax    = (1 + P.spec.busTolPct/100) * P.spec.busNom;

% --- 6. No reverse power ----------------------------------------------------
% A PV stage sourcing negative power is drawing from the bus through the array.
% Always a defect; costs nothing to check.
P.spec.minPanelPower = 0;       % [W] after startup

%% Simulation
% Left at Belal's own settings deliberately. ode23t with a 20 us ceiling is a
% reasonable choice for a switching Simscape model, and silently changing a
% teammate's solver to make your tests pass is how you produce a green harness
% and a broken product.
P.sim.startupBlank = 0.05;      % [s] ignore the first 50 ms everywhere: the
                                % Simscape initial transient is not a defect

end
