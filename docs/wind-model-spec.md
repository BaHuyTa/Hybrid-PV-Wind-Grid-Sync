# Wind Subsystem — Model Spec

**Owner:** Ba Huy Ta · **Weeks:** W5–W6, revised W7 · **Team 1, Smart Grid Technologies**

> **Revision, 6 September 2026 — DC-coupled, 60 kW.** The team's decision record of 5 September
> ([decisions.md](decisions.md)) sets the plant at 150 kVA for a 250 kW light-industrial site,
> **DC-coupled** on one shared 700 V bus with one grid-tie inverter, and rates the wind branch at
> **60 kW**. This supersedes the AC-coupled / 30 kW revision of 4 September, which was a response to
> the product owner's suggestion on 3 September; decisions.md records why that suggestion was not
> adopted at this scale (the two-topology comparison from that week is kept in
> [dc_vs_ac_coupled.png](dc_vs_ac_coupled.png)). The topology *inside* the wind branch is unchanged
> and so is its interface: a controlled current source into a regulated DC node. What changed is the
> rating (a clean 2× per-unit scaling from 30 kW, 20× from the original 3 kW) and the fact that the
> node it feeds is shared with PV again. Every measurement below was re-run at 60 kW on 6 September.

## 1. Topology decision

```
wind v(t) → Cp(λ,β) rotor → single-mass shaft → PMSG → 3φ diode bridge → boost + MPPT → shared DC bus (700 V) → 150 kVA inverter → PCC
```

Passive diode bridge + boost, **not** an active front end.

Rationale: this makes the wind branch structurally identical to the PV branch (source → boost → DC
bus). Same converter model, same MPPT interface, same contract with the DC node. An active rectifier
would add a machine-side dq current loop and speed loop to the control pair's workload, and no
success criterion in §2.2 of the proposal measures generator-side performance.

**Why the boost is there at all.** The architecture diagram labels the wind front end "rectifier +
boost". The boost is what does the MPPT. Without it, a diode bridge feeding the 700 V bus directly
would need V_rect above 700 V at *every* wind speed — but V_rect is proportional to rotor speed, so
at cut-in it is a third of rated. The alternatives are an active rectifier (the control cost above)
or a generator wound for ~2.1 kV open-circuit at rated. The boost is the cheap answer, and it is the
one PV uses too.

Accepted limitation: the 6-pulse bridge draws non-sinusoidal stator current, so there is a
6th-harmonic torque ripple on the shaft. It does not propagate past the boost and does not affect any
graded metric. **Quantified** (`scripts/wind_thd_check.m`, switched model at rated, 6 Sep 2026):
stator current THD **15.6%**, 5th 13.9%, 7th 6.5%, 11th 2.2%, no triplens. Lower than the
ideal 31% because the ~0.19 pu stator reactance gives a long commutation overlap. The 6·f_e ripple
reaching the DC bus is 1.26 A on 95 A, 1.3%. What the bus does see is the boost diode's
10 kHz pulse train: 125 A amplitude, which on the 44 mF bus capacitor
(`TestHarness/config/harnessParams.m`) is 0.045 V of ripple — negligible against the 5% criterion.

## 2. Layers and blocks

| Layer | Implementation | Notes |
|---|---|---|
| Aerodynamics | Cp(λ,β), Heier form, MATLAB Function block | β fixed at 0 (no pitch) |
| Drivetrain | Single lumped inertia J + viscous damping B | two-mass torsional not modelled — no criterion needs it |
| Generator | Simscape PMSM block, round rotor (Ld = Lq), sinusoidal back-EMF, generator convention | |
| Rectifier | 3φ uncontrolled diode bridge + DC-side L, small C | |
| Boost + MPPT | Same topology as PV boost; P&O on measured P_dc, or optimal torque control | see MPPT below |

Cp coefficients (standard set): c1 = 0.5176, c2 = 116, c3 = 0.4, c4 = 5, c5 = 21, c6 = 0.0068
→ Cp_max ≈ 0.48 at λ_opt ≈ 8.1.

    1/λi = 1/(λ + 0.08β) − 0.035/(β³ + 1)
    Cp   = c1·(c2/λi − c3·β − c4)·exp(−c5/λi) + c6·λ
    Pm   = 0.5·ρ·A·Cp·v³

**MPPT:** both are built and selectable via `wp.mppt_mode`. **The default is optimal torque
control (mode 1), which is a change from the original plan** — P&O is retained as mode 0, not deleted.

The evidence, from `scripts/wind_scenarios.m` (tracking efficiency, both modes, same scenarios,
60 kW plant, 6 Sep 2026):

| Scenario | P&O | torque control |
|---|---|---|
| steady at rated | 96.1% | 99.9% |
| step 8 → 12 m/s | 90.4% | 98.4% |
| **ramp 4 → 12 m/s** | **74.1%** | **98.5%** |
| IEC extreme gust | 99.3% | 99.9% |
| cut-in / cut-out | 91.5% | 93.9% |
| turbulent | 96.6% | 98.1% |

The figures are the same as at 3 kW and 30 kW to within a tenth of a point, and they should be:
every quantity the trackers see is per-unit identical (same λ, same duty, same rotor time constant).
P&O did **not** fail the way the spec predicted. It does not hunt under turbulence, and it reverses
direction on only ~half the perturbations. It fails on a *sustained ramp*: while the wind is rising,
the measured power goes up after **every** perturbation regardless of which way the perturbation
went, so P&O reads every step as a success and keeps walking the wrong way. Over the ramp, λ drifts
from ~8 down to ~5.2 while the duty *rises* — exactly when it should be falling to let the rotor
speed up. `scripts/wind_ramp_figure.m` draws it.

This is the same class of defect as the falling-irradiance ramp the PV harness found. Same
algorithm, same blind spot, different plant.

P&O also needs `Ts_mppt = 5 s`, not the 0.1–0.5 s of the original plan: the perturbation period
has to be longer than the 4.78 s rotor settling time, or P&O measures the rotor's transient
instead of the new steady state. The full tuning sweep is in `scripts/wind_mppt_sweep.m` and the
table is recorded in `params/windParams.m`.

**This needs the team's ratification**, because the roadshow Q&A committed us publicly to sharing
one MPPT algorithm with the PV branch. Mode 0 still does that and still works — it just costs
~25 points of capture on ramps.

## 3. Parameters — 60 kW

| Quantity | 60 kW | 30 kW (4 Sep draft) | 3 kW (proposal) | Basis |
|---|---|---|---|---|
| Rated electrical power | **60 kW** | 30 kW | 3 kW | decisions.md, 5 Sep 2026: 250 kW site, 26% renewable fraction |
| Rated wind speed | 12 m/s | 12 m/s | 12 m/s | assumed — see §3a |
| Cut-in wind speed | 4 m/s | 4 m/s | 4 m/s | set by max boost duty 0.85 |
| Air density ρ | 1.225 kg/m³ | | | |
| Rotor radius R | **6.463 m (D = 12.93 m)** | 4.570 m | 1.445 m | P = 0.5ρACp v³ at 66.7 kW mechanical |
| Rated shaft speed | **15.04 rad/s (144 rpm)** | 21.3 rad/s | 67.3 rad/s | λ_opt·v/R |
| Pole pairs p | **20** | 16 | 10 | direct drive, f_e ≈ 48 Hz (assumed — see below) |
| PM flux linkage λ_pm | **0.804 Wb** | 0.711 Wb | 0.360 Wb | sets V_rect ≈ 400 V at rated |
| Inertia J | **1768 kg·m²** | 442 kg·m² | 4.42 kg·m² | H = 3 s |
| Rectified DC voltage | 400 V rated, 133 V at cut-in | same | same | 1.35·V_ll |
| Boost duty (no-load) | 0.429 rated, 0.810 at cut-in | same | same | 1 − V_in/V_out, V_out = 700 V |
| Boost inductor current, rated | **~196 A** | ~98 A | ~9.8 A | P/V_rect under load |
| Current into the DC bus, rated | **~95 A** | ~47 A | ~4.7 A | P/V_dc — 44% of the bus's 214 A rating |
| Boost inductor L | 0.25 mH (ESR 5 mΩ) | 0.5 mH (10 mΩ) | 5 mH (100 mΩ) | same ~35% pk-pk ripple at rated |
| Stator Rs, Ls | 0.025 Ω, 0.9 mH | 0.05 Ω, 1.6 mH | 0.5 Ω, 8 mH | same pu: Rs ≈ 0.017 pu, Xs ≈ 0.19 pu |
| Rectifier-side C | 2 mF | 1 mF | 100 µF | same pu impedance |

**What the rescale did and did not change.** Every voltage, every duty, λ_opt, Cp, the inertia
constant and therefore every time constant are the same numbers as at 3 kW and 30 kW. Power,
current and inertia scale with the rating; rotor radius with its square root; impedances inversely.
That is deliberate: it means the validated operating points, the P&O tuning and the
bandwidth-separation argument all carry over per-unit, and the harness confirms it rather than
re-discovering it.

The one genuinely new choice at each rescale is the pole count. The 60 kW rotor turns at 144 rpm,
so at p = 10 the electrical frequency would be 24 Hz and at the 30 kW choice of p = 16, 38 Hz.
p = 20 gives 48 Hz; a 150 rpm direct-drive machine wound for 50 Hz has 20 pole pairs, so this is a
conventional machine, not an exotic one. Only λ_pm and the pu stator inductance depend on it.

### 3a. Where the sizing sits against real 60 kW turbines

The question the product owner would ask first is whether a 60 kW turbine is a real product or
whether we should model two 30 kW units. It is a real product class — checked 6 Sep 2026:

| Turbine | Rotor | Rated wind | Generator | Source |
|---|---|---|---|---|
| Aeolos-H 60 kW | 22.3 m | 9 m/s (cut-in 3 m/s) | direct-drive PMG, pitch-regulated | [windturbinestar.com](https://www.windturbinestar.com/60kw-wind-turbine.html) |
| Danish Wind Turbines 60 kW | 16.3 m (208 m²) | — | — | [wind-turbine-models.com](https://en.wind-turbine-models.com/turbines/1394-danish-wind-turbines-60-kw) |
| IMPEC 60 kW | — | — | PM synchronous | [wind-turbine-models.com](https://en.wind-turbine-models.com/turbines/1869-impec-60kw) |
| **this spec** | **12.9 m** | **12 m/s** | PMSG, 400 V rectified, stall (fixed pitch) | `params/windParams.m` |

So: **one 60 kW machine, not two 30 kW.** Two units would add a second rotor, a second rectifier
and boost, and the question of how the two MPPTs share one bus — new modelling for no graded
benefit, since the DC bus sees the same 60 kW either way.

Ours is the smallest and fastest rotor by a clear margin, because 12 m/s rated and Cp = 0.48 are
both optimistic. The rotor scales as v_rated^−1.5, so re-rating at **10 m/s** (the only change:
`wp.v_rated = 10`) gives a 17.0 m rotor at 91 rpm, and at **9 m/s** a 19.9 m rotor at 74 rpm —
which is the 18–21 m band the README quotes for real 60 kW machines, and matches the Aeolos-H
rated speed. At 12 m/s the 10 m/s rotor would make 104 kW, which is why the real machines pitch or furl.
Everything in this document scales through `windParams.m`, so the change is mechanical — but it
moves every wind-side number (and at 74 rpm the pole count would need to rise again to keep f_e
near 50 Hz), so it is question 4 in §7, not a decision I have taken.

Duty stays inside 0.85 across the whole operating range, so the boost never saturates.

**Measured correction.** The duty figures above are the *no-load* estimate — they use the
open-circuit rectified voltage. Under load the rectifier droops (commutation overlap plus winding
resistance), so V_rect is lower and the real duty is higher: **0.520 at rated, not 0.429**,
and 0.818 at cut-in against the 0.85 ceiling. The headroom claim survives, but only just —
at cut-in there are about three points of duty left, so cut-in is genuinely set by the boost
ceiling as assumed. Below cut-in (3 m/s) the boost saturates at 0.85 and simply delivers less,
which is correct behaviour.

All values above verified by `wind_model_check.m` (MATLAB R2026a).

## 4. Interface contract (Hoang — integration; Aqib / Duc — DC-link loop)

**Inputs:** `v_wind` [m/s], `v_dc` [V] measured at the shared DC bus, `enable` [bool]
**Output:** `i_dc` [A] injected into the DC bus node, plus a telemetry bus
(`omega_m`, `lambda`, `Cp`, `P_mech`, `P_dc`, `duty`, `mppt_state`)

The subsystem presents itself to the bus as a **controlled current source**, exactly as PV does.
The block interface has not changed through any of the three ratings or the AC-coupled detour.

> **The DC-bus capacitor is NOT inside this subsystem.** C_dc lives with the DC-link voltage loop
> in the integration model and the test harness (`P.plant.C = 44 mF`,
> `TestHarness/config/harnessParams.m`), owned by Hoang. Exactly one place owns C_dc or the bus
> dynamics are wrong.

**What the wind branch looks like to the DC-link loop** (for the control pair and the harness):
at rated it injects ~95 A of the bus's 214 A rating. Its largest transient is the 8 → 12 m/s
step (S2), which takes `i_src` from ~28 A to ~95 A over ~5 s — far slower than the
harness's 0 → 200 A source step, so it is a benign disturbance for the 200 ms loop. The
`source_step` and `cloud_transient` cases in `TestHarness/inputs/createTestInputs.m` already
bound it. Nothing in the wind branch assumes anything about the inverter beyond "the bus voltage
is regulated".

**Power limit — dropped.** The 4 September draft specified a `P_lim` input for proportional
sharing under curtailment. Behind the meter with a 250 kW site load, the plant never exports at
full generation (120 kWp + 60 kW < 250 kW), so there is no curtailment case in the success
criteria and the input is not built. The design notes stand if it is ever wanted: a fixed-pitch
rotor must curtail on the low-λ (stall) side, and the achievable depth shrinks towards cut-in.

**Sample times:** power stage at `Ts_power`; boost current loop at `Ts_ctrl` (matched to PV);
MPPT at `Ts_mppt`.

**Bandwidth separation** — so the cascade tuning holds:

| Loop | Owner | Target speed |
|---|---|---|
| Grid-side inner current loop | Aqib / Duc | 2 ms settling (§2.2) |
| DC-link voltage loop | Aqib / Duc | ~10× slower, 200 ms recovery (§2.2) |
| Source-side boost + MPPT | Huy / Belal | ~10× slower again |

Three clean decades. The wind branch is quasi-static from the DC-link loop's point of view, which
is what lets the cascade be tuned inside-out per the §4 risk note.

**Verified separation — unchanged at 60 kW.** Simulating the single-mass rotor under ideal
optimal-torque control (best case — P&O is slower), a wind step 8 → 12 m/s takes **4.78 s** to
reach 95% of the new operating speed. That is 24× the 200 ms DC-link recovery spec and ~2400× the
2 ms current loop. The number is identical at 3, 30 and 60 kW because it depends only on H, λ_opt
and the Cp curve, none of which moved: write the rotor equation in per-unit speed and torque and
the rating cancels out.

Consequences worth stating to the team:

- The control pair does not need to model wind dynamics when tuning the DC-link loop. The speed
  gap is large enough that the loops cannot interact.
- The wind branch reaches the rest of the system only as a slow change in bus current. Whatever we
  find at low SCR is therefore a grid-side phenomenon, not a plant artefact.
- Conversely, the DC-link loop absorbs every wind transient. My job is to hand it a realistic
  disturbance; that is what the W7–W9 scenarios are for.

## 5. Fidelity — two variants, one parameter file

Both variants read the same `windParams.m`:

- **Averaged** — switching-function boost, algebraic bridge (V_dc = 1.35·V_ll with power balance),
  dq PMSG. Used for controller tuning and the SCR sweep (W11), where run count matters.
- **Switched** — real IGBT/diode blocks, discrete solver at Ts = 1 µs. Used for THD and final
  validation, and to confirm the averaged-model tuning survives switching (the "model fidelity"
  risk on page 5).

**Both are built and cross-validated at 60 kW.** `scripts/wind_fidelity_check.m` pins the rotor at
the rated operating point and compares them:

| | switched | averaged | diff |
|---|---|---|---|
| i_L | 196.0 A | 197.6 A | −0.82% |
| V_rect | 339.3 V | 337.4 V | +0.54% |
| duty | 0.520 | 0.519 | +0.04% |
| P_dc | 66 328 W | 66 471 W | −0.22% |

Under 1% on every quantity, so the averaged model can be trusted for the W11 SCR sweep. The
switched model also shows the 82 A pk-pk inductor ripple (42% of the mean, against
70.5 A predicted from V_rect·d/(L·f_sw)) that the averaged model cannot, by construction.

The rotor is pinned deliberately: it settles in ~5 s and the switched model runs at ~100–150× real
time, so a mechanically-settled switched run would take about 10 minutes. Pinning isolates
the converter, which is what the switched model is for.

**The cross-check has found three defects the averaged model could not show:**

1. **A duty feedforward that silently cancelled the current loop.** `d_ff = 1 − V_rect/V_dc` looks
   standard, but with a stiff bus the boost already forces `V_rect = (1−d)·V_dc` in steady state, so
   the feedforward is satisfied at *every* operating point and exactly cancels whatever the PI does.
   The averaged model hid it by happening to converge near the right answer anyway.
2. **Current sampling read the ripple minimum, not the mean.** Sampling once per switching period at
   a fixed carrier phase biased the measured current low by half the ripple, so the loop drove the
   true current ~18% above reference. Fixed with a centre-aligned (triangular) carrier, where the
   inductor current at the carrier peak equals its average. This is invisible in an averaged model
   by construction.
3. **(Found by the first rescale.) The boost diode was at Simscape's default 0.3 Ω on-resistance.**
   At 4.7 A that is 1.4 V and 7 W — invisible. At 95 A it would be 28 V and 2.7 kW, 4.5% of the
   rating, and it would have appeared in this table as a switched-vs-averaged gap that is not real.
   Every semiconductor now reads one parameter, `wp.Ron_dev` (1 mΩ), so the bridge, boost diode and
   IGBT cannot disagree. The lesson is general: a default that is negligible at one rating is a
   measurement error at another, and the only defence is that *no* block keeps a default —
   `wind_model_lint.m` enforces it.

## 6. Feeds into my W7–W9 test scenarios

- Step 8 → 12 m/s; ramp; IEC extreme operating gust; cut-in / cut-out transitions
- Turbulent wind: sum-of-sines about a Weibull mean
- **Worst-case combined:** PV irradiance step down at the same instant as a wind gust up, on the
  shared bus. This is the largest DC-link excursion the sources can produce together, and it is
  the natural extra scenario for `TestHarness/inputs/createTestInputs.m` once the wind branch's
  `i_dc` replaces the synthetic `i_src` step. Note it is *slower* than the synthetic step: the
  rotor adds 5 s of inertia in front of the gust.

## 6a. What is built, and how to run it

```
models/wind/
  windLib.slx        library: Aerodynamics + MPPT, shared by both models so they
                     cannot drift. Edit here, never in a copy.
  windPlantAvg.slx   averaged  - variable-step, ~15 s per 150 s run
  windPlantSw.slx    switched  - Simscape Electrical, fixed-step at Ts_power,
                     ~100–150x real time (a 0.3 s run takes ~45 s)
scripts/
  windSim.m               run one scenario against either model
  wind_model_check.m      sizing arithmetic (no Simulink needed)
  wind_mppt_sweep.m       open-loop duty sweep + P&O tuning table
  wind_scenarios.m        6 scenarios, 10 checks, both MPPT modes
  wind_fidelity_check.m   averaged vs switched cross-validation
  wind_ramp_figure.m      the S3 ramp plot: P&O vs torque control, lambda and P_dc
  wind_model_lint.m       structure: library links resolved, workspace bound to
                          windParams(), library locked, no literal design parameters
  wind_thd_check.m        FFT / THD on the switched model: stator current, current
                          into the DC bus, boost inductor current (6/6 checks)
```

```matlab
addpath(genpath('params'), genpath('scripts'), genpath('models'));
wind_model_check        % sizing closes
wind_model_lint         % structure: links, workspace, no literals
wind_scenarios          % 10/10
wind_fidelity_check     % 5/5, agreement under 1%
wind_thd_check          % 6/6, FFT of the switched model
```

Both models take their parameters from the model workspace, which is bound to
`windParams()` directly — there is no dependency on whatever is in the base
workspace, and no constant is stored in a block mask. **The 60 kW rescale touched no `.slx`
file**: every changed number is in `params/windParams.m`, and the lint confirms the models
still reference it and nothing else.

**Toolbox note.** This does *not* need Specialized Power Systems, and that is just as well:
`powerlib` is not installed on the lab image. The switched model is built from foundation
Simscape Electrical (`ee_lib`), which is present.

## 7. Open questions

1. **Hoang — the DC bus.** Confirm the wind branch's contract (`i_dc` + telemetry into the shared
   bus, C_dc owned by integration, 44 mF per the harness), and whether you want the wind `i_dc`
   as a harness input in place of the synthetic `i_src` step for the combined worst case (§6).
2. **Aqib / Duc — DC-link loop.** The wind branch's largest disturbance is ~28 → 95 A
   over 5 s. Is anything in the loop design sensitive to a slow ramp rather than a step
   (integrator windup against the 400 A limit, for instance)?
3. **Redhwan — SFS with two sources on one inverter.** Unchanged from the original design: one
   inverter, one SFS. Nothing wind-side affects the NDZ analysis.
4. **Everyone — 60 kW sizing assumptions.** 12 m/s rated / 4 m/s cut-in give a 12.9 m rotor at
   144 rpm. Real 60 kW machines are 16–22 m rated at ~9 m/s (§3a). Rating at 9–10 m/s gives
   17–20 m and lands inside that range. Do we re-rate, or keep 12 m/s and say so? Either is one
   line in `windParams.m`; the harness re-runs in about half an hour.
5. Belal — the PV branch still uses the same boost topology and the same P&O, so we share one
   implementation on the bus?
6. **Everyone — the MPPT default is optimal torque control, not P&O.** Section 2 has the
   measurements. P&O is still there as `wp.mppt_mode = 0`. This changes what we can claim about
   sharing one algorithm with PV, so it needs a decision rather than my say-so.
7. Belal — does the PV branch's P&O show the same ramp defect? Mine does, and the mechanism is
   general. Worth pointing the PV harness at a sustained irradiance ramp specifically.
8. **Belal — boost, not buck.** The product owner asked and nobody in the room could answer. One
   written sentence in the PV spec: string voltage against the 700 V bus.
