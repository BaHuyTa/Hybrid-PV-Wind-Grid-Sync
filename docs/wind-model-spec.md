# Wind Subsystem — Model Spec (draft for Wed 19 Aug)

**Owner:** Ba Huy Ta · **Weeks:** W5–W6 · **Team 1, Smart Grid Technologies**

## 1. Topology decision

```
wind v(t) → Cp(λ,β) rotor → single-mass shaft → PMSG → 3φ diode bridge → boost + MPPT → DC link (700 V)
```

Passive diode bridge + boost, **not** an active front end.

Rationale: this makes the wind branch structurally identical to the PV branch (source → boost →
bus). Same converter model, same MPPT algorithm, same interface to the DC node. An active
rectifier would add a machine-side dq current loop and speed loop to the control pair's workload,
and no success criterion in §2.2 of the proposal measures generator-side performance.

Accepted limitation: the 6-pulse bridge draws non-sinusoidal stator current, so there is a 6th-harmonic
torque ripple on the shaft. It does not propagate past the DC link and does not affect any graded metric.

## 2. Layers and blocks

| Layer | Implementation | Notes |
|---|---|---|
| Aerodynamics | Cp(λ,β), Heier form, MATLAB Function or SPS Wind Turbine block | β fixed at 0 (no pitch) |
| Drivetrain | Single lumped inertia J + viscous damping B | two-mass torsional not modelled — no criterion needs it |
| Generator | Simscape PMSM block, round rotor (Ld = Lq), sinusoidal back-EMF, generator convention | |
| Rectifier | 3φ uncontrolled diode bridge + DC-side L, small C | |
| Boost + MPPT | Same topology as PV boost; P&O on measured P_dc | perturb period 0.1–0.5 s (slow, to respect rotor inertia) |

Cp coefficients (standard set): c1 = 0.5176, c2 = 116, c3 = 0.4, c4 = 5, c5 = 21, c6 = 0.0068
→ Cp_max ≈ 0.48 at λ_opt ≈ 8.1.

    1/λi = 1/(λ + 0.08β) − 0.035/(β³ + 1)
    Cp   = c1·(c2/λi − c3·β − c4)·exp(−c5/λi) + c6·λ
    Pm   = 0.5·ρ·A·Cp·v³

**MPPT:** both are now built and selectable via `wp.mppt_mode`. **The default is optimal torque
control (mode 1), which is a change from the plan above** — P&O is retained as mode 0, not deleted.

The evidence, from `scripts/wind_scenarios.m` (tracking efficiency, both modes, same scenarios):

| Scenario | P&O | torque control |
|---|---|---|
| steady at rated | 96.1% | 99.9% |
| step 8 → 12 m/s | 90.3% | 98.4% |
| **ramp 4 → 12 m/s** | **74.0%** | **98.5%** |
| IEC extreme gust | 99.3% | 99.9% |
| cut-in / cut-out | 91.5% | 93.7% |
| turbulent | 96.5% | 98.1% |

P&O did **not** fail the way the spec predicted. It does not hunt under turbulence (96.5%, and it
reverses direction on only ~half the perturbations). It fails on a *sustained ramp*: while the wind
is rising, the measured power goes up after **every** perturbation regardless of which way the
perturbation went, so P&O reads every step as a success and keeps walking the wrong way. Over the
ramp, λ drifts from 7.98 down to 5.18 while the duty *rises* — exactly when it should be falling to
let the rotor speed up.

This is the same class of defect as the falling-irradiance ramp the PV harness found. Same
algorithm, same blind spot, different plant.

P&O also needs `Ts_mppt = 5 s`, not the 0.1–0.5 s written above: the perturbation period has to be
longer than the 4.78 s rotor settling time, or P&O measures the rotor's transient instead of the new
steady state. At 0.1 s it scores 26–56%. The full tuning sweep is in `scripts/wind_mppt_sweep.m` and
the table is recorded in `params/windParams.m`.

**This needs the team's ratification**, because the roadshow Q&A commits us publicly to sharing one
MPPT algorithm with the PV branch. Mode 0 still does that and still works — it just costs ~25 points
of capture on ramps.

## 3. Indicative parameters (to confirm in W5 sizing)

| Quantity | Value | Basis |
|---|---|---|
| Rated electrical power | 3 kW | proposal |
| Rated wind speed | 12 m/s | assumed |
| Cut-in wind speed | 4 m/s | set by max boost duty 0.85 |
| Air density ρ | 1.225 kg/m³ | |
| Rotor radius R | 1.445 m (D = 2.89 m) | from P = 0.5ρACp v³ at ~3.3 kW mechanical |
| Rated shaft speed | 67.3 rad/s (642 rpm) | λ_opt·v/R |
| Pole pairs p | 10 | direct drive, f_e ≈ 107 Hz |
| PM flux linkage λ_pm | 0.360 Wb | sets V_rect ≈ 400 V at rated |
| Inertia J | 4.42 kg·m² | H = 3 s |
| Rectified DC voltage | 400 V rated, 133 V at cut-in | 1.35·V_ll |
| Boost duty | 0.429 rated, 0.810 at cut-in | 1 − V_in/V_out, V_out = 700 V |

Duty stays inside 0.85 across the whole operating range, so the boost never saturates.

**Measured correction.** The duty figures above are the *no-load* estimate — they use the
open-circuit rectified voltage. Under load the rectifier droops (commutation overlap plus winding
resistance), so V_rect is lower and the real duty is higher: **0.52 at rated, not 0.429**, and 0.818
at cut-in against the 0.85 ceiling. The headroom claim survives, but only just — at cut-in there is
about 4% of duty left, so cut-in is genuinely set by the boost ceiling as section 3 assumed. Below
cut-in (3 m/s) the boost saturates at 0.85 and simply delivers less, which is correct behaviour.

All values above verified by `wind_model_check.m` (MATLAB R2026a), cross-checked independently.

## 4. Interface contract (for Hoang — integration)

**Inputs:** `v_wind` [m/s], `v_dc` [V] measured at the bus, `enable` [bool]
**Output:** `i_dc` [A] injected into the DC-link node, plus a telemetry bus
(`omega_m`, `lambda`, `Cp`, `P_mech`, `P_dc`, `duty`, `mppt_state`)

The subsystem presents itself to the bus as a **controlled current source**, same as PV.

> **The DC-link capacitor is NOT inside this subsystem.** It lives in the integration model and is
> owned by Hoang. Exactly one place owns C_dc or the bus dynamics are wrong.

**Sample times:** power stage at `Ts_power`; boost current loop at `Ts_ctrl` (matched to PV);
MPPT at `Ts_mppt` = 0.1 s.

**Bandwidth separation** — so the cascade tuning holds:

| Loop | Owner | Target speed |
|---|---|---|
| Grid-side inner current loop | Aqib / Duc | 2 ms settling (§2.2) |
| DC-link voltage loop | Aqib / Duc | ~10× slower, 200 ms recovery (§2.2) |
| Source-side boost + MPPT | Huy / Belal | ~10× slower again |

Three clean decades. The wind branch is quasi-static from the DC-link loop's point of view, which
is what lets the cascade be tuned inside-out per the §4 risk note.

**Verified separation.** Simulating the single-mass rotor under ideal optimal-torque control
(best case — P&O is slower), a wind step 8 → 12 m/s takes **4.78 s** to reach 95% of the new
operating speed. That is 24× the 200 ms DC-link recovery spec and ~2400× the 2 ms current loop.

Consequences worth stating to the team:

- The control pair does not need to model wind dynamics when tuning. The speed gap is large enough
  that the loops cannot interact.
- The wind branch cannot destabilise the grid-side controllers. Whatever we find at low SCR is a
  grid-side phenomenon, not a plant artifact — which is exactly the claim the project needs to make.
- Conversely, the DC-link voltage loop absorbs every wind transient. My job is to hand it a
  realistic disturbance; that is what the W7–W9 scenarios are for.

## 5. Fidelity — two variants, one parameter file

Both variants read the same `windParams.m`:

- **Averaged** — switching-function boost, algebraic bridge (V_dc = 1.35·V_ll with power balance),
  dq PMSG. Used for controller tuning and the SCR sweep (W11), where run count matters.
- **Switched** — real IGBT/diode blocks, discrete solver at Ts = 1–2 µs. Used for THD and final
  validation, and to confirm the averaged-model tuning survives switching (the "model fidelity"
  risk on page 5).

Deliver both by end of W6 so W7 tuning is never blocked on model choice.

**Both are built and cross-validated.** `scripts/wind_fidelity_check.m` pins the rotor at the rated
operating point and compares them:

| | switched | averaged | diff |
|---|---|---|---|
| i_L | 9.78 A | 9.87 A | −0.91% |
| V_rect | 339.9 V | 337.8 V | +0.62% |
| duty | 0.520 | 0.519 | +0.20% |
| P_dc | 3302 W | 3324 W | −0.66% |

Under 1% on every quantity, so the averaged model can be trusted for the W11 SCR sweep.

The rotor is pinned deliberately: it settles in ~5 s and the switched model runs at ~190× real time,
so a mechanically-settled switched run would take ~16 minutes. Pinning isolates the converter, which
is what the switched model is for.

**The cross-check earned its keep — it found two defects the averaged model could not show:**

1. **A duty feedforward that silently cancelled the current loop.** `d_ff = 1 − V_rect/V_dc` looks
   standard, but with a stiff bus the boost already forces `V_rect = (1−d)·V_dc` in steady state, so
   the feedforward is satisfied at *every* operating point and exactly cancels whatever the PI does.
   The averaged model hid it by happening to converge near the right answer anyway.
2. **Current sampling read the ripple minimum, not the mean.** Sampling once per switching period at
   a fixed carrier phase biased the measured current low by half the ripple, so the loop drove the
   true current ~18% above reference. Fixed with a centre-aligned (triangular) carrier, where the
   inductor current at the carrier peak equals its average. This is invisible in an averaged model
   by construction.

## 6. Feeds into my W7–W9 test scenarios

- Step 8 → 12 m/s; ramp; IEC extreme operating gust; cut-in / cut-out transitions
- Turbulent wind: sum-of-sines about a Weibull mean
- **Worst-case combined:** PV irradiance step down at the same instant as a wind gust up — the
  largest DC-link excursion, and the real test of the 5% deviation / 200 ms recovery criterion

## 6a. What is built, and how to run it

```
models/wind/
  windLib.slx        library: Aerodynamics + MPPT, shared by both models so they
                     cannot drift. Edit here, never in a copy.
  windPlantAvg.slx   averaged  - variable-step, ~2 s per 150 s run
  windPlantSw.slx    switched  - Simscape Electrical, fixed-step at Ts_power,
                     ~190x real time (a 0.2 s run takes ~40 s)
scripts/
  windSim.m               run one scenario against either model
  wind_model_check.m      sizing arithmetic (no Simulink needed)
  wind_mppt_sweep.m       open-loop duty sweep + P&O tuning table
  wind_scenarios.m        6 scenarios, 10 checks, both MPPT modes
  wind_fidelity_check.m   averaged vs switched cross-validation
```

```matlab
addpath(genpath('params'), genpath('scripts'), genpath('models'));
wind_model_check        % sizing closes
wind_scenarios          % 10/10
wind_fidelity_check     % 5/5, agreement under 1%
```

Both models take their parameters from the model workspace, which is bound to
`windParams()` directly — there is no dependency on whatever is in the base
workspace, and no constant is stored in a block mask.

**Toolbox correction for the README.** This does *not* need Specialized Power
Systems, and that is just as well: `powerlib` is not installed on the lab image
(`toolbox/physmod/sps` contains only a stub). The switched model is built from
foundation Simscape Electrical (`ee_lib`), which is present. Anyone who followed
the README's stated requirement would have gone looking for a product that is
not there.

## 7. Open questions for Wednesday

1. Belal — confirming PV uses the same boost topology and the same P&O so we share one implementation?
2. Hoang — agree `i_dc` + telemetry bus as the interface, and that you own C_dc?
3. Aqib / Duc — is the ~10× separation between the DC-link loop and our source loops enough headroom
   for your cascade tuning, or do you want us slower?
4. Anyone — is 12 m/s rated / 4 m/s cut-in acceptable, or do we match a real 3 kW turbine datasheet?
5. **Everyone — the MPPT default is now optimal torque control, not P&O.** Section 2 has the
   measurements. P&O is still there as `wp.mppt_mode = 0`. This changes what we can claim about
   sharing one algorithm with PV, so it needs a decision rather than my say-so.
6. Belal — does the PV branch's P&O show the same ramp defect? Mine does, and the mechanism is
   general. Worth pointing the PV harness at a sustained irradiance ramp specifically.
