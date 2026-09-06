classdef tPVStage < matlab.unittest.TestCase
%TPVSTAGE Spec compliance tests for the PV boost + P&O MPPT stage.
%
%   Run from MATLAB:
%       results = runtests("tPVStage")
%
%   Roughly four minutes: every scenario is a Simscape switching simulation of
%   one to four seconds, and the reference sweeps behind them are cached but not
%   free the first time.
%
%   THIS SUITE IS CURRENTLY RED, AND THAT IS THE CORRECT STATE.
%   The model under test is Belal's solarsimulink.slx as delivered, and it does
%   not yet meet the interface spec in pv/pvParams.m. The failures are the
%   report. They are deliberately NOT marked as expected failures or filtered
%   into a known-issues list: a suite that has been taught to go green on a
%   subsystem that will not integrate is worse than no suite, because it removes
%   the one signal that would have stopped it reaching integration week.
%
%   The tests are split into two groups for exactly that reason:
%
%     meetsSpec*         claims about the MODEL. Red means the model needs work.
%     harness*           claims about the HARNESS itself. Red means the
%                        measurements above cannot be trusted and nothing else
%                        in this file means anything.
%
%   If both groups are red, fix the harness group first.
%
%   Nothing here knows how to simulate a model or how to compute a tracking
%   efficiency. It calls runPVScenario for a run and evaluatePVSpec for numbers,
%   then does the one thing a test is for: turning numbers into a verdict with a
%   message that says what to do next.

    properties (TestParameter)
        % Each scenario is its own test case, so a failure names the operating
        % point that broke rather than saying "testEverything failed".
        scenario = {"full_sun", "partial_600", "low_light_250", ...
                    "cloud_step_down", "cloud_step_up", "cloud_ramp"}
    end

    methods (TestClassSetup)
        function addHarnessToPath(testCase)
            import matlab.unittest.fixtures.PathFixture
            pvDir = fileparts(fileparts(mfilename("fullpath")));
            root  = fileparts(pvDir);
            testCase.applyFixture(PathFixture({ ...
                pvDir, ...
                fullfile(root, "config"), ...
                fullfile(root, "models")}));
        end
    end

    methods (Test)

        %% ---- Claims about the model ---------------------------------------

        function meetsSpec(testCase, scenario)
            % Every requirement this scenario declares must hold, as delivered.
            [out, P, meta, ref] = runPVScenario(scenario, Variant = "nominal");
            m = evaluatePVSpec(out, P, meta, ref);

            names = string(fieldnames(m.checks))';
            for name = names
                c = m.checks.(name);
                if ~c.applicable
                    continue    % this requirement does not apply here
                end
                msg = sprintf("[%s / nominal] %s: measured %.4f %s against a " + ...
                              "limit of %.4f %s.\n  %s", ...
                              scenario, name, c.value, c.units, c.limit, ...
                              c.units, meta.description);
                if c.dir == "min"
                    testCase.verifyGreaterThanOrEqual(c.value, c.limit, msg);
                else
                    testCase.verifyLessThanOrEqual(c.value, c.limit, msg);
                end
            end
        end

        %% ---- Claims about the harness -------------------------------------

        function harnessReferenceIsIndependentAndReachable(testCase)
            % Tracking efficiency is a ratio, and it means nothing if the
            % denominator is itself saturated: a controller stuck on the duty
            % rail scores 100 % against a ceiling that is stuck on the same
            % rail. Every irradiance the scenarios use must have an INTERIOR
            % maximum, or the corresponding tracking result must be withdrawn.
            for G = [250 400 500 600 1000]
                ref = pvReference(G, pvParams(), Quiet = true);
                testCase.verifyGreaterThan(ref.Pmax, 0, ...
                    sprintf("Reference sweep at %d W/m^2 found no positive power.", G));
                testCase.verifyTrue(ref.reachable, ...
                    sprintf("Reference at %d W/m^2 peaks at D = %.3f, on a duty " + ...
                            "rail. Tracking efficiency against this ceiling is " + ...
                            "not a meaningful number and evaluatePVSpec should " + ...
                            "be withdrawing it.", G, ref.Dmpp));
            end
        end

        function harnessVariantActuallyChangesTheModel(testCase)
            % A variant that silently failed to apply would produce two
            % identical runs, and the report would read as proof that the
            % perturbation size does not matter -- the exact opposite of the
            % truth. buildPVModels raises if the patch misses; this checks the
            % result rather than trusting the raise.
            buildPVModels("nominal");
            buildPVModels("fastPO");
            root = fileparts(fileparts(mfilename("fullpath")));

            dD = zeros(1, 2);
            names = ["pvUUT", "pvUUT_fastPO"];
            for k = 1:2
                if ~bdIsLoaded(names(k))
                    load_system(fullfile(root, "models", names(k) + ".slx"));
                end
                chart = sfroot().find("-isa", "Stateflow.EMChart", ...
                            "Path", char(names(k) + "/MPPT Controller/PO MPPT"));
                tok = regexp(chart.Script, "dD\s*=\s*([\d.eE+-]+)\s*;", "tokens", "once");
                testCase.assertNotEmpty(tok, ...
                    "Could not read dD out of " + names(k) + ".");
                dD(k) = str2double(tok{1});
            end

            testCase.verifyEqual(dD(1), 0.002, ...
                "pvUUT should carry the delivered perturbation size.", ...
                AbsTol = 1e-12);
            testCase.verifyEqual(dD(2), 0.010, ...
                "pvUUT_fastPO should carry the patched perturbation size.", ...
                AbsTol = 1e-12);
        end

        function harnessSeparatesTrendFromDither(testCase)
            % Regression test for a real bug in this harness.
            %
            % Reacquisition was first measured on power averaged over ONE
            % perturbation period. A stage whose steady dither is wider than the
            % tracking band then never counts as settled -- it keeps dipping
            % back out, so "the last time it was outside" walks forward to the
            % end of the run. fastPO on cloud_ramp reported 1.77 s that way when
            % the trend had arrived in 0.27 s, and the wrong number was
            % plausible enough to be believed: it looked like the faster
            % controller had made reacquisition worse, when what it had actually
            % done was trade reacquisition for ripple.
            %
            % The fix is a slower average for the trend. This locks it in.
            [out, P, meta, ref] = runPVScenario("cloud_ramp", Variant = "fastPO");
            m = evaluatePVSpec(out, P, meta, ref);

            testCase.verifyLessThan(m.reacquireTime, 0.5, ...
                "The trend filter should see cloud_ramp/fastPO reacquire in " + ...
                "about 0.27 s. A value near the run length means reacquisition " + ...
                "is being measured on the dither again.");

            % ...and the dither must still be visible to the ripple check,
            % otherwise the trend filter has simply hidden the trade-off.
            testCase.verifyGreaterThan(m.powerRipplePct, P.spec.powerRipplePct, ...
                "cloud_ramp/fastPO should FAIL the ripple spec. If it passes, " + ...
                "the ripple metric has been smoothed along with the trend and " + ...
                "the cost of the faster controller has gone invisible.");
        end

        function harnessDoesNotReportUncheckedRequirements(testCase)
            % A metric printed next to a requirement that was never evaluated is
            % worse than no metric: both halves are true and the combination is
            % nonsense. Not-applicable checks must carry NaN limits so no
            % downstream reader can accidentally compare against one.
            [out, P, meta, ref] = runPVScenario("full_sun", Variant = "nominal");
            m = evaluatePVSpec(out, P, meta, ref);

            testCase.verifyFalse(m.checks.reacquire.applicable, ...
                "full_sun holds irradiance constant, so there is nothing to " + ...
                "reacquire from and the check should not apply.");
            testCase.verifyTrue(isnan(m.checks.reacquire.limit), ...
                "A check that does not apply must not carry a limit.");
            testCase.verifyTrue(m.checks.reacquire.pass, ...
                "A check that does not apply must not be able to fail a run.");
        end

        function harnessGeneratedModelsAreCurrent(testCase)
            % Catches the classic stale-artifact failure: someone edits the
            % source or the build script, forgets to rebuild, and the harness
            % certifies a model nobody is shipping.
            buildPVModels("nominal");
            pvDir = fileparts(fileparts(mfilename("fullpath")));
            root  = fileparts(pvDir);

            src = dir(fullfile(fileparts(root), "Belal's PV", "solarsimulink.slx"));
            bld = dir(fullfile(pvDir, "buildPVModels.m"));
            uut = dir(fullfile(root, "models", "pvUUT.slx"));

            testCase.assertNotEmpty(src, "Source model not found.");
            testCase.assertNotEmpty(uut, "pvUUT.slx was not built.");
            testCase.verifyGreaterThan(uut.datenum, src.datenum, ...
                "pvUUT.slx is older than the source model it was built from.");
            testCase.verifyGreaterThan(uut.datenum, bld.datenum, ...
                "pvUUT.slx is older than buildPVModels.m.");
        end

    end
end
