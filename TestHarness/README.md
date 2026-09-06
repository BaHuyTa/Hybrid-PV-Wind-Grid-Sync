# Test Harness — Hybrid PV-Wind Grid Synchronisation

Reusable test scaffolding for validating Simulink subsystems against a written
spec, built during W5–W7 of the Application Studio B capstone.

**Read [`docs/DESIGN_NOTES.md`](docs/DESIGN_NOTES.md) first** — it explains why
every piece exists and what breaks without it.

## Quick start

```matlab
cd("...\ProjectDevelopment_MATLAB\TestHarness")   % wherever you cloned it
setupHarness                                     % run this FIRST, once per session

runAll                              % full report + regression check
runAll(Report = true)               % + standalone HTML report in results/reports
runtests("tests/tDCLinkLoop.m")     % the automated test suite
```

Expected: **9/9 tests pass**, **6/6 scenarios meet spec**, **no drift**.

`setupHarness` is not optional bookkeeping — it fixes four things that will
otherwise cost you an afternoon each. Read its help text for the details:

1. Adds the five source folders to the path.
2. Redirects Simulink's build cache to `%LOCALAPPDATA%`, so ~1 MB of binary
   artifacts per run stops syncing to everyone else through OneDrive.
3. Puts `P` in the base workspace. Every block references `P.ctrl.*` rather
   than a literal, so the model cannot compile without it — and the error
   Simulink gives you when it is missing names no cause.
4. Clears the read-only flag OneDrive sets on synced folders, which otherwise
   makes Simulink Test refuse to run with `ExternalHarnessDirNotWritable`
   even though writing works fine.

> **`addpath(genpath("TestHarness"))` does not work if you are already inside
> `TestHarness`** — it looks for a nested folder of the same name, finds
> nothing, and silently adds nothing. Use `setupHarness`.

## Two ways to test

| | `runtests("tests/tDCLinkLoop.m")` | `model_test` on `tests/dcLinkLoop.feature` |
|---|---|---|
| Scenarios | all 6 | 4 — Gherkin has only `const()` and `step()`, so `source_ramp` and `cold_start` cannot be expressed |
| Decision coverage | 100% (4/4) | 75% (3/4) |
| Spec limits | from `harnessParams.m` | hard-coded literals in the `.feature` |
| Failure detail | measured vs limit | condition, signal ranges, a `.mat` of the run, repro code |
| Regression baselines | yes | no |

Both catch the deliberately-detuned `sluggish` controller. They are
complementary: `matlab.unittest` is the spec-and-regression backbone, Gherkin
is the fast loop when you are hunting a specific bug. Gherkin needs the
Simulink Agentic Toolkit — `setupHarness(Toolkit = true)`.

## What is here

| Path | Role |
|---|---|
| `config/harnessParams.m` | Every parameter and every spec limit, in one place |
| `models/buildDCLinkLoop.m` | Builds the model from plain-text source |
| `models/DCLinkLoop.slx` | Build artifact — regenerate, don't hand-edit |
| `inputs/createTestInputs.m` | The six canonical test scenarios |
| `run/runScenario.m` | The only place the model is simulated |
| `run/evaluateSpec.m` | Turns a run into metrics and verdicts |
| `run/runAll.m` | One-button report, SDI logging, regression check |
| `tests/tDCLinkLoop.m` | The `matlab.unittest` suite |
| `results/baseline/` | Stored reference runs for regression comparison |

## The model under test

A DC-link voltage regulation loop — a capacitor bus fed by the PV and wind
stages, with a PI controller commanding grid-side inverter current to hold the
bus steady. It is a real slice of the project (Aqib's W8–W9 DC voltage loop),
chosen so the harness you learn on is a scale model of the harness you ship.

```
C · dVdc/dt = i_src − i_out
```

## Common commands

| Goal | Command |
|---|---|
| Watch the deliberately-bad design fail | `runAll(Variant = "sluggish")` |
| Inspect one scenario | `[out,P,meta,ds] = runScenario("cold_start")` |
| Record a new baseline | `runAll(SaveBaseline = true)` |
| Compare runs visually | `Simulink.sdi.view` |
| Rebuild the model from source | `P = harnessParams(); buildDCLinkLoop()` |

⚠️ Saving a baseline blesses current behaviour as correct. A baseline saved from
a broken run makes every future regression check agree with the breakage.

## Pointing it at a teammate's model

Four things change; the rest carries over unchanged. See §11 of the design
notes — and note that step 1 (write the spec *before* looking at their model) is
the one that actually prevents integration-week failures.

## Testing a teammate's model: the PV stage

`pv/` applies the same architecture to Belal's `solarsimulink.slx` (PV array →
boost converter → P&O MPPT). The original file is never modified —
`buildPVModels` copies it and instruments the copy, because a model you have
edited can no longer answer "was it already broken?"

```matlab
setupHarness
runPVAll                        % all six irradiance scenarios
runPVAll(Variant = "fastPO")    % the candidate fix: 5x P&O perturbation size
runtests("tPVStage")            % 5 harness self-tests + 6 spec tests
```

| Path | Role |
|---|---|
| `pv/pvParams.m` | Spec + variants. Written before measuring the model |
| `pv/buildPVModels.m` | Instruments a copy: driveable irradiance, logged signals |
| `pv/pvReference.m` | Duty sweep with the MPPT removed — the independent ceiling |
| `pv/pvScenarios.m` | Six irradiance profiles + which requirements apply to each |
| `pv/evaluatePVSpec.m` | Metrics and verdicts |
| `pv/runPVAll.m` | Verdict table + findings written as sentences |
| `pv/tests/tPVStage.m` | The suite |

Three things had to be solved before the model could be tested at all, and they
are the reusable lesson rather than PV specifics:

1. **Irradiance was a `Constant` block.** Nothing could drive it. Replaced with
   `From Workspace` in the copy, so one mechanism covers held, stepped and
   ramped profiles.
2. **The four interesting signals went to a `Scope` and nowhere else.** A Scope
   is a window, not a record. Logging is set on the *port* handle — line-level
   `DataLogging` was removed in R2026a.
3. **There was no reference to score against.** Tracking efficiency is a ratio,
   and its denominator cannot come from the algorithm under test. `pvSweep.slx`
   is the same plant with P&O replaced by a fixed duty; sweeping it gives the
   best power the hardware could deliver if the controller were perfect.

> **`runtests("tPVStage")` is currently red on `meetsSpec`, and that is correct.**
> The delivered model does not meet the interface spec. The failures are the
> report. The five `harness*` tests are the ones that must stay green — if they
> fail, nothing the spec tests say can be trusted. Fix those first.
