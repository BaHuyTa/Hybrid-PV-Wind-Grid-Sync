# Test Harness — Design Notes

These notes explain *why* the harness is built the way it is. The code says what
it does; this file says why it does it that way, what breaks if you skip a
piece, and what went wrong while building it.

Written for Hoang (integration lead, W5–W7 test harness block) on the hybrid
PV–wind grid synchronisation project.

---

## 1. What a test harness actually is

A test harness is the reusable scaffolding around a model:

- a library of **standard inputs** you can feed any subsystem,
- **automated checks** that turn the output into pass/fail,
- a **record** of every run so you can tell what changed.

It is not a test. It is the thing that makes writing tests cheap. Once the
harness exists, adding a seventh scenario is four lines; without it, every test
is a fresh half-hour of wiring scopes and squinting at waveforms.

**Why it is the integration lead's job.** By W8 you will receive five models
built independently by five people who never ran them against each other. If
something misbehaves then, the question "why doesn't the system work" has no
answer — the fault could be in any of five models or in how you wired them.
With a harness, every subsystem is validated against its own written spec
*before* it touches the shared DC bus, so a W8 failure is almost certainly the
integration, not a hidden bug in someone's PV model.

---

## 2. Why this particular model

The model under test is a **DC-link voltage regulation loop**: a capacitor bus
fed by the PV and wind stages, with a controller commanding the grid-side
inverter current to hold the bus voltage steady.

It was chosen deliberately over a throwaway toy:

- It is genuinely simple — eleven blocks, no Simscape, ~0.2 s to simulate.
- It is a real slice of your project. It is Aqib's W8–W9 "DC volt loop".
- Its pass/fail criteria (settling time, overshoot, steady-state error, current
  limit) are the same *shape* as the ones the real harness will need.

So the harness you learn on is a scale model of the harness you will ship, not
a doll.

### The physics

A DC-link capacitor obeys:

```
C · dVdc/dt = i_src − i_out
```

- `i_src` — current injected by the PV and wind stages (**disturbance input**)
- `i_out` — current the grid-side inverter pulls out (**control variable**)

The controller regulates `Vdc` by commanding `i_out`. The inner current loop is
much faster than this outer voltage loop, so it is modelled as a first-order lag
(`1/(τ_i·s + 1)`, τ_i = 1 ms) rather than in full. That is standard practice:
model the fast loop's *effect*, not its internals, when you are studying the
slow loop.

---

## 3. Sign convention — read this before touching the model

The error is defined **measured minus reference**:

```
e = Vdc − Vdc_ref
```

That is the opposite of the textbook `e = ref − measured`, and it is not a typo.

Here is why it works. The plant transfer from `i_out` to `Vdc` carries a
negative sign (pulling *more* current out makes the voltage go *down*). Using
`ref − measured` as well would give two sign inversions and require negative PI
gains to be stable, which reads as a bug to anyone reviewing it. Flipping the
error definition instead means the PI gains stay positive and the loop is
stable.

Sanity check it by perturbation, which is more reliable than sign-chasing:

> `Vdc` rises above setpoint → `e > 0` → PI increases `i_out` → more current is
> pulled out of the capacitor → `Vdc` falls back. ✅ Negative feedback.

In the model this is the `Error` Sum block with signs `"-+"`: input 1
(`Vdc_ref`) is subtracted, input 2 (`Vdc` feedback) is added.

---

## 4. The four layers

```
  Test input library      inputs/createTestInputs.m
          ↓                 "what does the world do?"
  Model under test        models/DCLinkLoop.slx
          ↓                 built by models/buildDCLinkLoop.m
  Measurement + checks    run/evaluateSpec.m
          ↓                 "what do the numbers say?"
  Verdict and record      tests/tDCLinkLoop.m, run/runAll.m
                            "pass or fail, and did it change?"
```

The layers are separate on purpose. Each split prevents a specific failure:

| Split | Prevents |
|---|---|
| Inputs separate from tests | Five slightly different definitions of "a step" |
| Metrics separate from tests | A test that passes while your plot disagrees |
| One simulation entry point | "Passes in the test, fails when I run it manually" |
| Build script separate from `.slx` | Six people producing unmergeable binaries |

---

## 5. File by file

### `config/harnessParams.m`
Every number the model needs and every limit the tests check, in one file.
Nothing is typed into a block dialog by hand — blocks reference `P.ctrl.Kp`,
`P.plant.C`, and so on. Change a value here and both the model and the tests
follow.

Two variants: `"nominal"` (correctly tuned) and `"sluggish"` (deliberately
under-tuned, fails the spec). The sluggish one exists to prove the harness can
detect a bad design.

### `models/buildDCLinkLoop.m`
Constructs the model from scratch, block by block, and saves it.

**Why a build script instead of committing the `.slx`?** An `.slx` is a binary
zip. Two people editing it produce two files that cannot be merged or diffed —
you can only pick one and lose the other's work. On a six-person team sharing a
OneDrive folder, that will happen. A build script is plain text: it diffs, it
reviews, and anyone can regenerate an identical model. The `.slx` becomes a
build artifact, not a source file.

It also makes sabotage recoverable — see §8, where a deliberately broken model
was restored with one function call.

### `inputs/createTestInputs.m`
The six canonical scenarios. Answers "what does the world do to the model?" and
contains no assertions. Keeping it assertion-free means you can run any scenario
just to look at it, and several tests can share one waveform.

| Scenario | What it represents |
|---|---|
| `source_step` | PV and wind come up: `i_src` steps 0 → 10 A |
| `source_ramp` | Irradiance rises gradually over 100 ms |
| `cloud_transient` | Cloud covers the array: `i_src` drops 10 → 2 A |
| `reference_step` | Operator raises the setpoint: 700 → 750 V |
| `cold_start` | Bus starts at 650 V and must charge |
| `overload` | `i_src` steps to 60 A, past the 20 A inverter limit |

### `run/runScenario.m`
The **only** place the model is simulated. Both interactive exploration and the
automated tests come through here.

This matters more than it looks. If the tests built their own `SimulationInput`
and you built a different one by hand at the command line, you would eventually
hit the worst class of bug: "it passes the test but fails when I run it", or the
reverse. One entry point makes that impossible.

It also rebuilds the `.slx` automatically if `buildDCLinkLoop.m` is newer —
which stops the classic failure where someone edits the build script, forgets to
re-run it, and tests the stale model.

### `run/evaluateSpec.m`
Turns a run into five numbers and a verdict per requirement. Measures; does not
throw. That is what lets the same code serve the test suite *and* a plain report
— so a test and a chart can never disagree about what "settling time" means.

### `tests/tDCLinkLoop.m`
The `matlab.unittest` suite. Nine tests, ~2.6 s.

Run it with:

```matlab
runtests("tests/tDCLinkLoop.m")
```

or open MATLAB's Test Browser and press Run.

> **Why `matlab.unittest` and not Simulink Test's Gherkin format?**
> Simulink Test *is* licensed here, but the Gherkin bridge depends on MCP
> tooling that was not loaded, and — more importantly — your teammates should be
> able to run these tests from plain MATLAB with no Claude Code and no MCP
> setup. `matlab.unittest` is native, works in the Test Browser, and supports
> parameterized tests, which fits a scenario × variant matrix exactly.

### `run/runAll.m`
The one-button entry point. Runs every scenario, prints a report, pushes runs to
the Simulation Data Inspector, and checks for regressions against a stored
baseline.

---

## 6. Not every requirement applies to every scenario

This is the part that is easy to get wrong, and it is worth understanding
properly.

During `overload`, the source pushes in 60 A while the inverter is only allowed
to remove 20 A. The surplus 40 A charges the capacitor and the bus voltage
climbs without bound — it reaches about 4.5 kV. **That is physics, not a
defect.**

A harness that asserted voltage regulation there would report a failure on every
single run. Within a week everyone would learn to ignore that red mark, and the
one assertion that genuinely matters — *did the 20 A current limit hold?* —
would be lost in the noise. A test suite people ignore is worse than no test
suite, because it costs time and buys false confidence.

So each scenario declares `meta.applies`, the subset of requirements meaningful
for it. `overload` declares only `currentLimit`. The report says so out loud
rather than printing a bare "PASS":

```
overload    4563.22   0.2500   4563.22   20.00   pass (only currentLimit applies)
```

`overload` also has a second assertion guarding the first: it verifies the bus
*did* lose regulation. Without that, someone lowering the 60 A step to 15 A
would turn the whole test into a no-op that still shows green.

---

## 7. How the numbers were chosen

The spec was written **before** the controller was tuned. That ordering is the
whole point — a spec written after the fact just describes whatever you happened
to build.

Tuning rule for both variants:

```
Kp = C · ωc          places the loop crossover at ωc
Ki = Kp · ωc/10      places the PI zero a decade below crossover
```

The only thing that changes between variants is `ωc`. Measured against a 10 A
source step:

| ωc (rad/s) | Peak deviation | % of 700 V | Settling |
|---:|---:|---:|---:|
| 40 | 95.6 V | 13.66 % | 0.450 s |
| 100 | 38.8 V | 5.54 % | 0.187 s |
| 150 | 26.2 V | 3.74 % | 0.101 s |
| **200** | **19.9 V** | **2.85 %** | **0.062 s** |
| 400 | 10.9 V | 1.56 % | 0.015 s |

Spec limits are 5 % overshoot and 100 ms settling.

- **ωc = 100 was rejected**: 5.54 % overshoot, just past the 5 % limit. The
  first tuning attempt failed its own spec — the harness earned its keep on run
  one.
- **ωc = 150 was rejected too**: it met the overshoot spec, but settled at
  100.5 ms against a 100 ms limit. A design that only just passes is a design
  that fails after the next change.
- **ωc = 200 was chosen**: real margin on both (2.85 % vs 5 %, 62 ms vs 100 ms),
  phase margin ≈ 73°.

`sluggish` uses ωc = 40: fails both overshoot and settling, by a wide enough
margin that there is no ambiguity about whether the harness caught it.

---

## 8. Bugs found while building this

Every one of these was found *by* the harness, and every one is the kind of
thing that silently corrupts results.

**1. Overshoot reported as 0.00 V on a run that clearly overshot.**
The metric picked its "approach direction" with `sign(vrefFinal − VdcAtStart)`.
When the bus sat at 700.0000001 V instead of exactly 700, `sign()` returned −1,
so the code looked for an excursion *below* the setpoint, found none, and
reported zero overshoot. Comparing floating-point values for exact equality
failed silently **and in the flattering direction** — the worst combination.
Fixed by using the tolerance band as a deadband rather than comparing to zero.

**2. Two scenarios were measuring their own startup transient.**
`cloud_transient` and `reference_step` both carry 10 A from t = 0, so the
inverter current starts at zero and spends ~60 ms catching up. Firing the event
at 50 ms measured the startup transient *plus* the event and blamed the event.
Fixed by delaying those events to 200 ms. **A test must isolate the thing it
claims to measure.**

**3. Measuring "overshoot" as deviation-from-reference is wrong for a
reference step.** During a 700 → 750 V step the tracking error momentarily
reaches 50 V, but that is the commanded change, not overshoot. Overshoot is only
whatever exceeds 750 V. Fixed by measuring excursion past the *final* setpoint.

**4. `DataLogging` lives on the port handle, not the line handle.**
Setting it on the line errors out. The *line* carries the signal `Name`; the
output *port* carries `DataLogging`. Related: `LimitDataPoints` is forced off,
because left on, Simulink keeps only the last 5000 samples and the beginning of
the run silently disappears — which would make every startup assertion check the
wrong data. (This project has been bitten by truncated logs before.)

**5. `ExternalInput` specified twice.** Setting `LoadExternalInput` as both a
model parameter and via `setExternalInput` raises *"ExternalInput needs to be
specified only once"*. It is switched on in the build script and left alone
afterwards.

---

## 9. Spec tests vs regression baselines — they answer different questions

This distinction is the single most useful idea in the harness.

- **Spec tests** ask: *is this acceptable?*
- **Regression baselines** ask: *did this change?*

You need both, and here is the proof. The DC-link capacitance was nudged by 5 %
and everything re-run:

```
6 of 6 scenarios meet every requirement that applies to them.

--- Regression check against baseline ---
  reference_step    Vdc waveform      max point difference 1.147 V
  cold_start        maxCurrent         14.9665 ->  15.1444  (+0.1780)
  overload          overshoot         4563.2234 -> 4346.3031  (-216.9203)
```

**Every spec test still passed.** The design was still acceptable. But something
had changed, and the baseline caught it.

That is exactly the situation you will be in during W8–W10 when five people are
editing five models. Most changes will still pass the spec. The question you
actually need answered is *"which of you changed something, and was it on
purpose?"*

The regression tolerances are not "how much error is acceptable" — the spec
already covers that. They are "how much change is worth telling a human about".

⚠️ **Saving a baseline blesses the current behaviour as correct.** A baseline
saved from a broken run makes every future regression check agree with the
breakage. Do it deliberately, never casually.

---

## 10. How to run it

```matlab
cd("C:\Users\Khiem\OneDrive - UTS\Courses\2026B_Application Studio B\TestHarness")
addpath("config", "inputs", "run", "models", "tests")
```

| Goal | Command |
|---|---|
| Full report + regression check | `runAll` |
| Run the test suite | `runtests("tests/tDCLinkLoop.m")` |
| Watch the bad design fail | `runAll(Variant = "sluggish")` |
| Look at one scenario | `[out,P,meta,ds] = runScenario("cold_start")` |
| Record a new baseline | `runAll(SaveBaseline = true)` |
| Compare runs visually | `Simulink.sdi.view` |
| Rebuild the model from source | `P = harnessParams(); buildDCLinkLoop()` |

Expected clean result: **9/9 tests pass**, **6/6 scenarios meet spec**, **no
drift**.

---

## 11. Pointing this at a teammate's model

The harness is deliberately generic. To validate Belal's PV model or Aqib's
SRF-PLL, four things change and nothing else:

1. **Write the spec first**, in `harnessParams.m`, before looking at their
   model. For the PLL: lock time, steady-state phase error, frequency overshoot
   during a phase jump. For the PV MPPT: settling time and percentage of
   available power captured.
2. **Add scenarios** to `createTestInputs.m` — grid voltage sag/swell, a phase
   jump, a frequency ramp for the PLL; irradiance and temperature profiles for
   the PV.
3. **Declare which requirements apply** to each scenario (`meta.applies`).
4. **Add the metrics** to `evaluateSpec.m`.

`runScenario`, `runAll`, and the whole regression mechanism carry over unchanged.

**Do this before W8.** The single highest-value thing in this list is step 1
applied across the team: pin down exactly what signals each subsystem exposes at
its boundary — names, units, sign conventions, sample rates — and write it down
while everyone is still building. Mismatched interface assumptions are what
actually blow up integration week, far more often than control theory does.

That is not a hypothetical for this project. An earlier debugging session lost
significant time to a PMSG initial condition given in rpm while the connected
block expected rad/s. Nothing was wrong with either model. The *interface*
between them was never written down.

---

## 12. Exercises

Work through these to go from reading the harness to owning it.

1. **Break it on purpose.** Change `P.ctrl.Kp` to `P.ctrl.Kp/10` in
   `harnessParams.m` and run `runtests`. Read the failure messages — do they
   tell you what to do?
2. **Loosen a spec until a real failure passes.** Set `overshootPct` to 20 and
   run `runAll(Variant = "sluggish")`. Notice `harnessCatchesRegression` is the
   test that objects. Understand why that test exists.
3. **Add a scenario.** A double disturbance: source steps up at 0.2 s, then a
   cloud at 0.35 s. Which requirements apply? What should `evalStart` be?
4. **Add a metric.** Peak `dVdc/dt` — the rate of voltage change, which matters
   for capacitor stress. Add it to `evaluateSpec.m` and give it a spec limit.
5. **Find the anti-windup bug.** `Current_Limit` saturates the controller output
   but the PI integrator does not know it. Drive the model hard enough to
   saturate for a sustained period and watch the integrator wind up. Then decide
   whether to fix it with the PID block's built-in anti-windup or leave it and
   document the limitation. *(Both are defensible; say which and why.)*
6. **Use SDI properly.** Run nominal, then sluggish, then open
   `Simulink.sdi.view` and overlay the two `Vdc` traces. This is what you will
   put in your W11 report.

---

## 13. One-paragraph summary

The harness feeds six canonical scenarios into a DC-link voltage loop, measures
five metrics from each run, checks only the requirements that genuinely apply to
each scenario, and compares everything against a stored baseline. Nine automated
tests run in under three seconds. It has been verified to catch a hard-coded
gain, a detuned controller, and a 5 % capacitance drift that every spec test
happily passed. The build script means the model is plain-text source your team
can diff, and `runScenario` being the only path to `sim()` means a test result
and a manual run can never disagree.
