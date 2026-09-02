classdef tDCLinkLoop < matlab.unittest.TestCase
%TDCLINKLOOP Automated spec compliance tests for the DC-link voltage loop.
%
%   Run from MATLAB:
%       results = runtests("tDCLinkLoop")
%   or open MATLAB's Test Browser and press Run.
%
%   Nothing in this file knows how to simulate the model or how to compute a
%   settling time. It calls runScenario to get a run and evaluateSpec to get
%   numbers, then does the one thing a test is for: turning numbers into a
%   verdict with a message that tells you what to do next.
%
%   That split is deliberate. Tests that also contain simulation setup and
%   metric maths grow into a second, divergent copy of the harness, and then
%   nobody can tell whether a failure means the model is wrong or the test is.

    properties (TestParameter)
        % Every scenario in the input library becomes its own test case, so a
        % failure report names the scenario that broke rather than saying
        % "testEverything failed".
        scenario = {"source_step", "source_ramp", "cloud_transient", ...
                    "reference_step", "cold_start", "overload"}
    end

    methods (TestClassSetup)
        function addHarnessToPath(testCase)
            import matlab.unittest.fixtures.PathFixture
            root = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(PathFixture({ ...
                fullfile(root, "config"), ...
                fullfile(root, "inputs"), ...
                fullfile(root, "run"),    ...
                fullfile(root, "models")}));
        end
    end

    methods (Test)

        function meetsSpec(testCase, scenario)
            % The main event: with the nominal controller, every requirement
            % that applies to this scenario must hold.
            [out, P, meta, ds] = runScenario(scenario, Variant = "nominal");
            m = evaluateSpec(out, ds, P, meta);

            names = string(fieldnames(m.checks))';
            for name = names
                c = m.checks.(name);
                if ~c.applicable
                    continue    % this requirement does not apply here
                end
                testCase.verifyLessThanOrEqual(c.value, c.limit, ...
                    sprintf("[%s / nominal] %s: measured %.4f %s, limit %.4f %s.\n%s", ...
                        scenario, name, c.value, c.units, c.limit, c.units, ...
                        meta.description));
            end
        end

        function harnessCatchesRegression(testCase)
            % A test suite that has never failed is a test suite you have no
            % reason to trust. This runs the deliberately under-tuned
            % controller and asserts that the harness NOTICES.
            %
            % If this test ever passes silently -- meaning the sluggish design
            % sailed through -- the harness has stopped working, even though
            % every other test is green. That is the failure mode this catches.
            failing = strings(0);
            for s = ["source_step", "cold_start"]
                [out, P, meta, ds] = runScenario(s, Variant = "sluggish");
                m = evaluateSpec(out, ds, P, meta);
                if ~m.allPass
                    failing(end+1) = s; %#ok<AGROW>
                end
            end

            testCase.verifyNotEmpty(failing, ...
                "The sluggish controller passed every check. Either the spec " + ...
                "limits have been loosened until they mean nothing, or " + ...
                "evaluateSpec has stopped measuring. Do not trust a green " + ...
                "suite until this test fails the sluggish variant again.");
        end

        function currentLimitHoldsUnderOverload(testCase)
            % Overload deserves its own test rather than being folded into
            % meetsSpec, because the interesting assertion is the opposite of
            % the usual one: regulation is EXPECTED to be lost, and what must
            % survive is the current limit.
            [out, P, meta, ds] = runScenario("overload", Variant = "nominal");
            m = evaluateSpec(out, ds, P, meta);

            testCase.verifyLessThanOrEqual(m.maxCurrent, P.spec.ImaxAbs, ...
                sprintf("Inverter current reached %.2f A against a %.2f A limit. " + ...
                        "The saturation block is not holding.", ...
                        m.maxCurrent, P.spec.ImaxAbs));

            % And confirm the scenario really is an overload, so this test
            % cannot quietly turn into a no-op if someone lowers the 60 A step.
            testCase.verifyGreaterThan(m.steadyStateError, P.spec.VdcTolAbs, ...
                "Overload scenario did not actually overload the bus. The " + ...
                "source step may have been reduced below the inverter limit, " + ...
                "which would make this test prove nothing.");
        end

        function parametersAreSingleSourceOfTruth(testCase)
            % Guards the design rule that no number is typed into a block
            % dialog by hand. Change a gain in harnessParams and the model must
            % follow; if a block has a hard-coded number instead of a P.*
            % reference, this catches it.
            P = harnessParams(); %#ok<NASGU>
            mdl = "DCLinkLoop";
            if ~bdIsLoaded(mdl)
                load_system(mdl);
            end
            testCase.addTeardown(@() close_system(mdl, 0));

            checks = { ...
                mdl + "/Voltage_PI",         "P",           "P.ctrl.Kp"; ...
                mdl + "/Voltage_PI",         "I",           "P.ctrl.Ki"; ...
                mdl + "/Current_Limit",      "UpperLimit",  "P.ctrl.Imax"; ...
                mdl + "/Inv_C",              "Gain",        "1/P.plant.C"; ...
                mdl + "/DC_Bus_Cap", "InitialCondition",    "P.plant.Vdc0"};

            for k = 1:size(checks, 1)
                actual = string(get_param(checks{k,1}, checks{k,2}));
                testCase.verifyEqual(actual, string(checks{k,3}), ...
                    sprintf("Block %s parameter %s is ""%s"" but should reference " + ...
                            "%s. A literal number here means the model and " + ...
                            "harnessParams.m can disagree.", ...
                            checks{k,1}, checks{k,2}, actual, checks{k,3}));
            end
        end

    end
end
