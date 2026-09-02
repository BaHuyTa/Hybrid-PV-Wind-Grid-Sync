function [ds, P, meta] = createTestInputs(scenario, P)
%CREATETESTINPUTS Canonical input waveforms for the DC-link loop model.
%
%   [ds, P, meta] = createTestInputs(scenario)
%   [ds, P, meta] = createTestInputs(scenario, P)
%
%   Returns a Simulink.SimulationData.Dataset wired to the model's two inports,
%   a possibly-modified parameter struct (some scenarios change the initial
%   condition), and a meta struct describing the scenario.
%
%   This file answers "what does the world do to the model, and which
%   requirements apply while it does it?" It contains no assertions -- the
%   pass/fail arithmetic lives in run/evaluateSpec.m and the assertions
%   themselves live in tests/.
%
%   Scenarios:
%     "source_step"      PV and wind come up: i_src steps 0 -> 10 A
%     "source_ramp"      irradiance rises gradually: i_src ramps 0 -> 10 A
%     "cloud_transient"  cloud covers the array: i_src drops 10 -> 2 A
%     "reference_step"   operator raises the setpoint: Vdc_ref 700 -> 750 V
%     "cold_start"       bus starts below setpoint at 650 V and must charge
%     "overload"         i_src steps to 60 A, far past what the 20 A inverter
%                        limit can absorb
%
%   NOT EVERY REQUIREMENT APPLIES TO EVERY SCENARIO.
%   This is the part that is easy to get wrong. During "overload" the source is
%   pushing in three times more current than the inverter is allowed to pull
%   out, so the bus voltage MUST run away -- that is physics, not a defect. A
%   harness that asserts voltage regulation there would report a failure every
%   run, everyone would learn to ignore it, and the one assertion that does
%   matter (the current limit held at 20 A) would be lost in the noise.
%
%   So each scenario declares meta.applies: the subset of spec items that are
%   meaningful for it. A test that checks everything everywhere is a test
%   nobody trusts.
%
%   Timing fields:
%     meta.stepTime   when the disturbance begins
%     meta.evalStart  when metrics start being measured. Usually the same as
%                     stepTime, but for a ramp it is the moment the ramp STOPS,
%                     because you cannot fairly measure "settling" while the
%                     input is still moving.

arguments
    scenario (1,1) string
    P struct = harnessParams()
end

stepTime = 0.05;   % all events begin here [s]

% Defaults, overridden per scenario below.
allSpecItems  = ["overshoot" "settling" "steadyState" "currentLimit"];
meta.applies  = allSpecItems;
meta.settleLimitField = "settleTime";

switch scenario
    case "source_step"
        meta.stopTime    = 0.5;
        meta.description = "PV and wind ramp up: source current steps 0 to 10 A";
        t     = timeVector(P, meta.stopTime);
        vref  = constant(P.ctrl.Vdc_ref, t);
        isrc  = 10 * (t >= stepTime);
        evalStart = stepTime;

    case "source_ramp"
        rampDur = 0.1;
        meta.stopTime    = 0.5;
        meta.description = "Irradiance rises gradually: source current ramps 0 to 10 A over 100 ms";
        t     = timeVector(P, meta.stopTime);
        vref  = constant(P.ctrl.Vdc_ref, t);
        isrc  = min(10, max(0, 10 * (t - stepTime) / rampDur));
        % Metrics start when the ramp finishes. Measuring settling from the
        % START of a 100 ms ramp charges the controller for time it spent
        % correctly following a moving input.
        evalStart = stepTime + rampDur;

    case "cloud_transient"
        % This scenario carries 10 A from t = 0, so the model starts with the
        % inverter current at zero and spends the first several tens of ms
        % catching up. Firing the cloud event at the usual 50 ms would measure
        % that startup transient plus the cloud, and report the sum as the
        % cloud's fault. The event is delayed to 200 ms so the bus is genuinely
        % settled first and the test isolates what it claims to.
        stepTime = 0.2;
        meta.stopTime    = 0.6;
        meta.description = "Cloud covers the array: source current drops 10 to 2 A";
        t     = timeVector(P, meta.stopTime);
        vref  = constant(P.ctrl.Vdc_ref, t);
        isrc  = 10 - 8 * (t >= stepTime);
        evalStart = stepTime;

    case "reference_step"
        % Same startup-overlap problem as cloud_transient, same fix.
        stepTime = 0.2;
        meta.stopTime    = 0.6;
        meta.description = "Setpoint raised: Vdc_ref steps 700 to 750 V";
        t     = timeVector(P, meta.stopTime);
        vref  = P.ctrl.Vdc_ref + 50 * (t >= stepTime);
        isrc  = constant(10, t);
        evalStart = stepTime;

    case "cold_start"
        meta.stopTime    = 0.5;
        meta.description = "Bus starts at 650 V and must charge to the 700 V setpoint";
        P.plant.Vdc0 = 650;              % <-- scenario changes the plant IC
        stepTime  = 0;                   % the "event" is switch-on, at t = 0
        t     = timeVector(P, meta.stopTime);
        vref  = constant(P.ctrl.Vdc_ref, t);
        isrc  = constant(10, t);
        evalStart = 0;
        % Charging a bus from cold is allowed to take longer than rejecting a
        % disturbance on an already-running bus, so the looser startup bound
        % applies here instead of the normal settling bound.
        meta.settleLimitField = "startupTime";

    case "overload"
        meta.stopTime    = 0.3;
        meta.description = "Source current steps to 60 A, past the 20 A inverter limit";
        t     = timeVector(P, meta.stopTime);
        vref  = constant(P.ctrl.Vdc_ref, t);
        isrc  = 60 * (t >= stepTime);
        evalStart = stepTime;
        % The source is forcing in 60 A and the inverter may only remove 20 A.
        % The surplus 40 A charges the capacitor and the bus voltage climbs
        % without bound. Losing regulation is the CORRECT behaviour, so the
        % voltage requirements are switched off and only one question is asked:
        % did the current limit actually hold?
        meta.applies = "currentLimit";

    otherwise
        error("createTestInputs:unknownScenario", ...
              "Unknown scenario ""%s"". See help createTestInputs.", scenario);
end

meta.scenario  = scenario;
meta.stepTime  = stepTime;
meta.evalStart = evalStart;

% Element names must match the model's inport names exactly. If someone renames
% an inport and forgets to change this, the sim errors instead of silently
% feeding the wrong signal to the wrong port -- which is the behaviour we want.
ds = Simulink.SimulationData.Dataset;
ds = ds.addElement(timeseries(vref, t), "Vdc_ref");
ds = ds.addElement(timeseries(isrc, t), "i_src");
end

% -----------------------------------------------------------------------------
function t = timeVector(P, stopTime)
%TIMEVECTOR Sample times matching the model's fixed step exactly.
% Building the input on the same grid the solver uses avoids interpolation
% between input samples, so a "step at 0.05 s" really does land on 0.05 s.
t = (0:P.sim.dt:stopTime)';
end

function v = constant(value, t)
%CONSTANT A constant signal shaped to the time vector.
v = value * ones(size(t));
end
