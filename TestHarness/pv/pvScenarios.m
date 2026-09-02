function [irrProfile, P, meta] = pvScenarios(scenario, P)
%PVSCENARIOS Irradiance profiles the PV stage has to cope with, and what each one proves.
%
%   [irrProfile, P, meta] = pvScenarios("full_sun")
%
%   Returns the irradiance waveform for the From Workspace block, the parameter
%   struct, and a meta struct describing the scenario. No assertions here: the
%   arithmetic lives in evaluatePVSpec, the assertions in tests/.
%
%   Scenarios:
%     "full_sun"         1000 W/m^2 held. STC. The easy case, and the one the
%                        model was almost certainly developed against.
%     "partial_600"      600 W/m^2 held. Overcast but bright -- an ordinary
%                        operating point, not an edge case.
%     "low_light_250"    250 W/m^2 held. Early morning, heavy cloud. The panel
%                        still has power worth taking.
%     "cloud_step_down"  1000 -> 500 instantly. A cloud edge crossing the array.
%     "cloud_step_up"    500 -> 1000 instantly. The other edge of the same cloud.
%     "cloud_ramp"       1000 -> 400 over one second. Thin overcast rolling in.
%
%   WHY THE STOP TIMES LOOK EXCESSIVE.
%   P&O perturbs duty by 0.002 every 10 ms, so the stage can move 0.2 of duty
%   per second and no faster. Getting from the 0.5 start to a low-light
%   operating point is over two seconds of travel before steady state even
%   begins. A one-second simulation would measure the journey and call it the
%   destination -- and would report a tracking failure that is really just an
%   unfinished run. Each stop time below allows the full slew plus a settled
%   window to measure in.
%
%   NOT EVERY REQUIREMENT APPLIES TO EVERY SCENARIO.
%   "reacquire" needs something to reacquire FROM, so it is meaningless on the
%   three held-irradiance runs. Asserting it there would fail every run for a
%   reason that is not a defect, and a harness that cries wolf gets ignored --
%   taking the checks that do matter down with it.

arguments
    scenario (1,1) string
    P struct = pvParams()
end

allSpecItems = ["tracking" "reacquire" "dutyRail" "ripple" "busBand" "power"];
held         = setdiff(allSpecItems, "reacquire", "stable");

meta.scenario = scenario;
meta.event    = NaN;          % when the irradiance change happens [s]

switch scenario
    case "full_sun"
        meta.description = "Full sun held at STC (1000 W/m^2)";
        meta.stopTime    = 1.5;
        meta.evalStart   = 1.0;
        meta.irrFinal    = 1000;
        meta.applies     = held;
        irrProfile = holdAt(1000, meta.stopTime);

    case "partial_600"
        meta.description = "Bright overcast held at 600 W/m^2";
        meta.stopTime    = 2.5;
        meta.evalStart   = 2.0;
        meta.irrFinal    = 600;
        meta.applies     = held;
        irrProfile = holdAt(600, meta.stopTime);

    case "low_light_250"
        meta.description = "Heavy cloud / early morning held at 250 W/m^2";
        meta.stopTime    = 4.0;
        meta.evalStart   = 3.5;
        meta.irrFinal    = 250;
        meta.applies     = held;
        irrProfile = holdAt(250, meta.stopTime);

    case "cloud_step_down"
        meta.description = "Cloud edge crosses the array: 1000 -> 500 W/m^2";
        meta.stopTime    = 4.0;
        meta.event       = 1.0;   % by which time the 1000 W/m^2 point is settled
        meta.evalStart   = 3.5;
        meta.irrFinal    = 500;
        meta.applies     = allSpecItems;
        irrProfile = stepAt(1000, 500, meta.event, meta.stopTime);

    case "cloud_step_up"
        meta.description = "Cloud clears: 500 -> 1000 W/m^2";
        meta.stopTime    = 4.0;
        meta.event       = 1.5;   % 500 W/m^2 is further from the 0.5 start, so
                                  % it needs longer to settle before the step
        meta.evalStart   = 3.5;
        meta.irrFinal    = 1000;
        meta.applies     = allSpecItems;
        irrProfile = stepAt(500, 1000, meta.event, meta.stopTime);

    case "cloud_ramp"
        meta.description = "Thin overcast rolls in: 1000 -> 400 W/m^2 over 1 s";
        meta.stopTime    = 4.0;
        meta.event       = 2.0;   % the moment the ramp STOPS. Measuring
                                  % settling while the input is still moving
                                  % scores the disturbance, not the response.
        meta.evalStart   = 3.5;
        meta.irrFinal    = 400;
        meta.applies     = allSpecItems;
        irrProfile = timeseries([1000; 1000; 400; 400], ...
                                [0; 1.0; meta.event; meta.stopTime]);

    otherwise
        error("pvScenarios:badScenario", ...
              "Unknown scenario ""%s"". See the help text for the list.", scenario);
end

meta.variant = P.ctrl.variant;
meta.runName = sprintf("%s [%s]", scenario, P.ctrl.variant);
end

% -----------------------------------------------------------------------------
function ts = holdAt(g, tEnd)
%HOLDAT Constant irradiance as a two-point profile.
ts = timeseries([g; g], [0; tEnd]);
end

% -----------------------------------------------------------------------------
function ts = stepAt(g0, g1, tStep, tEnd)
%STEPAT A step, built with a coincident pair of samples.
%   The two samples one microsecond apart are what make this a step rather than
%   a ramp: From Workspace interpolates linearly between samples, so a single
%   breakpoint would quietly turn every "step" scenario into a slow ramp over
%   the whole run -- and the model would sail through a test it was never
%   actually given.
ts = timeseries([g0; g0; g1; g1], [0; tStep; tStep + 1e-6; tEnd]);
end
