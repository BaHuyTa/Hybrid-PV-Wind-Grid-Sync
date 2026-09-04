# Wind Subsystem — Model Spec

**Owner:** Ba Huy Ta · **Weeks:** W5–W6, revised W7 · **Team 1, Smart Grid Technologies**

> **Revision, 4 September 2026 — AC-coupled, 30 kW.** After the product-owner meeting the
> system is **AC-coupled** (one DC link and one inverter per source, meeting on the AC bus at
> the PCC) and the wind branch is rated **30 kW**, not 3 kW. The topology *inside* the wind
> branch is unchanged. What changed: the rating (a clean 10× per-unit scaling), what the branch
> feeds (its own DC link 2, not a bus shared with PV), and where its transients go (the PCC,
> through inverter 2). See [dc_vs_ac_coupled.png](dc_vs_ac_coupled.png). The 3 kW figures are
> kept alongside where the comparison is instructive; everything else below is the 30 kW design.

## 1. Topology decision

```
wind v(t) → Cp(λ,β) rotor → single-mass shaft → PMSG → 3φ diode bridge → boost + MPPT → DC link 2 (700 V) → inverter 2 → AC bus
```

Passive diode bridge + boost, **not** an active front end.

Rationale: this makes the wind branch structurally identical to the PV branch (source → boost →
own DC link → own inverter). Same converter model, same MPPT interface, same contract with the
DC node — the only difference is which DC link each one feeds. An active rectifier would add a
machine-side dq current loop and speed loop to the control pair's workload, who now have two
grid-side inverters to build instead of one, and no success criterion in §2.2 of the proposal
measures generator-side performance.

**Why the boost stays under AC coupling.** The architecture diagram labels the wind front end
just "Rectifier". The boost is inside that box and it is what does the MPPT. Without it, a diode
bridge feeding inverter 2 directly would need V_rect above ~600 V (400 V grid line peak plus
SVPWM margin) at *every* wind speed the inverter operates at — but V_rect is proportional to
rotor speed, so at cut-in it is a third of rated. The alternatives are an active rectifier (the
control cost above) or a generator wound for ~1.8 kV open-circuit at rated with the inverter
absorbing the whole speed range. The boost is the cheap answer, and it is the one PV uses too.

Accepted limitation: the 6-pulse bridge draws non-sinusoidal stator current, so there is a 6th-harmonic
torque ripple on the shaft. It does not propagate past DC link 2 and does not affect any graded metric.

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
30 kW plant; 3 kW result in brackets):

| Scenario | P&O | torque control |
|---|---|---|
| steady at rated | 96.2% (96.1%) | 99.9% (99.9%) |
| step 8 → 12 m/s | 90.5% (90.3%) | 98.4% (98.4%) |
| **ramp 4 → 12 m/s** | **74.2%** (74.0%) | **98.5%** (98.5%) |
| IEC extreme gust | 99.3% (99.3%) | 99.9% (99.9%) |
| cut-in / cut-out | 91.5% (91.5%) | 93.9% (93.7%) |
| turbulent | 96.6% (96.5%) | 98.1% (98.1%) |

The rescale did not change the picture, and it should not have: every quantity the trackers see
is per-unit identical (same λ, same duty, same rotor time constant). P&O did **not** fail the way
the spec predicted. It does not hunt under turbulence, and it reverses direction on only ~half
the perturbations. It fails on a *sustained ramp*: while the wind is rising, the measured power
goes up after **every** perturbation regardless of which way the perturbation went, so P&O reads
every step as a success and keeps walking the wrong way. Over the ramp, λ drifts from ~8 down to
6.48 while the duty *rises* — exactly when it should be falling to let the rotor speed up.

This is the same class of defect as the falling-irradiance ramp the PV harness found. Same
algorithm, same blind spot, different plant.

P&O also needs `Ts_mppt = 5 s`, not the 0.1–0.5 s of the original plan: the perturbation period
has to be longer than the 4.78 s rotor settling time, or P&O measures the rotor's transient
instead of the new steady state. The full tuning sweep is in `scripts/wind_mppt_sweep.m` and the
table is recorded in `params/windParams.m`.

**This needs the team's ratification**, because the roadshow Q&A committed us publicly to sharing
one MPPT algorithm with the PV branch. Mode 0 still does that and still works — it just costs
~25 points of capture on ramps.

## 3. Parameters — 30 kW

| Quantity | 30 kW | 3 kW (was) | Basis |
|---|---|---|---|
| Rated electrical power | **30 kW** | 3 kW | product owner, 4 Sep 2026 |
| Rated wind speed | 12 m/s | 12 m/s | assumed |
| Cut-in wind speed | 4 m/s | 4 m/s | set by max boost duty 0.85 |
| Air density ρ | 1.225 kg/m³ | | |
| Rotor radius R | **4.570 m (D = 9.14 m)** | 1.445 m (D = 2.89 m) | P = 0.5ρACp v³ at 33.3 kW mechanical |
| Rated shaft speed | **21.3 rad/s (203 rpm)** | 67.3 rad/s (642 rpm) | λ_opt·v/R |
| Pole pairs p | **16** | 10 | direct drive, f_e ≈ 54 Hz (assumed — see below) |
| PM flux linkage λ_pm | **0.711 Wb** | 0.360 Wb | sets V_rect ≈ 400 V at rated |
| Inertia J | **442 kg·m²** | 4.42 kg·m² | H = 3 s |
| Rectified DC voltage | 400 V rated, 133 V at cut-in | same | 1.35·V_ll |
| Boost duty (no-load) | 0.429 rated, 0.810 at cut-in | same | 1 − V_in/V_out, V_out = 700 V |
| Boost inductor current, rated | **~95 A** | ~9.8 A | P/V_rect under load |
| Current into DC link 2, rated | **~45 A** | ~4.7 A | P/V_dc — this is inverter 2's DC rating |
| Boost inductor L | 0.5 mH (ESR 10 mΩ) | 5 mH (100 mΩ) | same ~35% pk-pk ripple at rated |
| Stator Rs, Ls | 0.05 Ω, 1.6 mH | 0.5 Ω, 8 mH | same pu: Rs ≈ 0.02 pu, Xs ≈ 0.22 pu |
| Rectifier-side C | 1 mF | 100 µF | same pu impedance |

**What the rescale did and did not change.** Every voltage, every duty, λ_opt, Cp, the inertia
constant and therefore every time constant are the same numbers as at 3 kW. Power, current and
inertia scale by 10; rotor radius by √10; impedances by 1/10. That is deliberate: it means the
validated operating points, the P&O tuning and the bandwidth-separation argument all carry over
per-unit, and the harness confirms it rather than re-discovering it.

The one genuinely new choice is the pole count. The 30 kW rotor turns 3.16× slower, so at p = 10
the electrical frequency would be 34 Hz; p = 16 gives 54 Hz. Commercial 30 kW direct-drive PM
generators are catalogued at 200, 300, 400 and 500 rpm (e.g. RX Energy's 30 kW radial-flux PMG
range; a 500 rpm / 400 V / 50 Hz unit from PMAC Motor), and a 200 rpm machine wound for 50 Hz has
15 pole pairs — so 16 at 203 rpm is a conventional machine, not an exotic one. Only λ_pm and the
pu stator inductance depend on it.

**Where the sizing sits against real 30 kW turbines** (vendor pages, checked 4 Sep 2026):

| Turbine | Rotor | Rated wind | Rated speed | Generator |
|---|---|---|---|---|
| Aeolos-H 30 kW | 15.6 m | 9 m/s | — | direct-drive PMG |
| Zenia Energy 30 kW | 13.8 m | — (cut-in 3 m/s) | — | — |
| Kodair KW30 | 14.1 m | ~11 m/s (32 kW) | — | — |
| Renery RW-30 | 13.5 m | 10 m/s | 90 rpm | PMG, 400 V DC on-grid |
| **this spec** | **9.1 m** | **12 m/s** | **203 rpm** | PMSG, 400 V rectified |

Ours is the smallest and fastest rotor by a clear margin, because 12 m/s rated and Cp = 0.48 are
both optimistic. Re-rating at **10 m/s** (the only change: `wp.v_rated = 10`) gives a 12.0 m rotor at
129 rpm, inside the commercial envelope; at 12 m/s that rotor would make 52 kW, which is why the
real machines pitch or furl. Everything in this document scales through `windParams.m`, so the
change is mechanical — but it moves every wind-side number, so it is question 4 in §7, not a
decision I have taken.

Duty stays inside 0.85 across the whole operating range, so the boost never saturates.

**Measured correction.** The duty figures above are the *no-load* estimate — they use the
open-circuit rectified voltage. Under load the rectifier droops (commutation overlap plus winding
resistance), so V_rect is lower and the real duty is higher: **0.520 at rated, not 0.429**,
and 0.818 at cut-in against the 0.85 ceiling. The headroom claim survives, but only just —
at cut-in there are about three points of duty left (0.818 against 0.85), so cut-in is genuinely set by the boost ceiling
as assumed. Below cut-in (3 m/s) the boost saturates at 0.85 and simply delivers less, which is
correct behaviour.

All values above verified by `wind_model_check.m` (MATLAB R2026a).

## 4. Interface contract (Hoang — integration; Aqib / Duc — inverter 2)

**Inputs:** `v_wind` [m/s], `v_dc` [V] measured at **DC link 2**, `enable` [bool]
**Output:** `i_dc` [A] injected into the **DC link 2** node, plus a telemetry bus
(`omega_m`, `lambda`, `Cp`, `P_mech`, `P_dc`, `duty`, `mppt_state`)

The subsystem presents itself to DC link 2 as a **controlled current source**, exactly as PV
does to DC link 1. The block interface is unchanged from the DC-coupled design; only what sits
on the other side of it changed.

> **The DC-link capacitor is NOT inside this subsystem.** C_dc2 lives with inverter 2 in the
> integration model and is owned by Hoang, the same rule as before now applied per link.
> Exactly one place owns each C_dc or the link dynamics are wrong.

**What inverter 2 has to be** (for the control pair): 30 kW — about 45 A DC at 700 V and 43 A rms
per phase at 400 V — with its DC link held at 700 V by its own voltage loop, plus its own SRF-PLL,
dq current loop and SFS. That is the PV inverter's design at six times the rating. Nothing in the
wind branch assumes anything about the inverter beyond "the link voltage is regulated".

**Sample times:** power stage at `Ts_power`; boost current loop at `Ts_ctrl` (matched to PV);
MPPT at `Ts_mppt`.

**Bandwidth separation** — so the cascade tuning holds:

| Loop | Owner | Target speed |
|---|---|---|
| Grid-side inner current loop (each inverter) | Aqib / Duc | 2 ms settling (§2.2) |
| DC-link voltage loop (each inverter) | Aqib / Duc | ~10× slower, 200 ms recovery (§2.2) |
| Source-side boost + MPPT | Huy / Belal | ~10× slower again |

Three clean decades. The wind branch is quasi-static from the DC-link-2 loop's point of view, which
is what lets the cascade be tuned inside-out per the §4 risk note.

**Verified separation — unchanged at 30 kW.** Simulating the single-mass rotor under ideal
optimal-torque control (best case — P&O is slower), a wind step 8 → 12 m/s takes **4.78 s** to
reach 95% of the new operating speed. That is 24× the 200 ms DC-link recovery spec and ~2400× the
2 ms current loop. The number is identical to the 3 kW result because it depends only on H, λ_opt
and the Cp curve, none of which moved: write the rotor equation in per-unit speed and torque and
the rating cancels out.

Consequences worth stating to the team:

- The control pair does not need to model wind dynamics when tuning either inverter. The speed
  gap is large enough that the loops cannot interact.
- There is no longer a DC path from the wind branch to the PV branch. The wind branch reaches
  the rest of the system only as a change in what inverter 2 exports, at rotor speed. Whatever we
  find at low SCR is therefore a grid-side phenomenon — and specifically the two-inverters-on-one-PCC
  interaction that the DC-coupled design avoided by construction.
- Conversely, inverter 2's DC-link loop absorbs every wind transient on its own. My job is to
  hand it a realistic disturbance; that is what the W7–W9 scenarios are for.

## 5. Fidelity — two variants, one parameter file

Both variants read the same `windParams.m`:

- **Averaged** — switching-function boost, algebraic bridge (V_dc = 1.35·V_ll with power balance),
  dq PMSG. Used for controller tuning and the SCR sweep (W11), where run count matters.
- **Switched** — real IGBT/diode blocks, discrete solver at Ts = 1 µs. Used for THD and final
  validation, and to confirm the averaged-model tuning survives switching (the "model fidelity"
  risk on page 5).

**Both are built and cross-validated at 30 kW.** `scripts/wind_fidelity_check.m` pins the rotor at
the rated operating point and compares them:

| | switched | averaged | diff |
|---|---|---|---|
| i_L | 98.0 A | 98.9 A | −0.91% |
| V_rect | 339.2 V | 337.1 V | +0.63% |
| duty | 0.520 | 0.520 | −0.05% |
| P_dc | 33175 W | 33237 W | −0.19% |

Under 1% on every quantity, so the averaged model can be trusted for the W11 SCR sweep. P_dc
agreement actually improved from −0.66% at 3 kW to −0.19%, which is the boost-diode fix below
doing its job. The switched model also shows the 41 A pk-pk inductor ripple (41% of the mean,
against 35 A predicted from V_rect·d/(L·f_sw)) that the averaged model cannot, by construction.

The rotor is pinned deliberately: it settles in ~5 s and the switched model runs at ~250× real
time, so a mechanically-settled switched run would take ~21 minutes. Pinning isolates the
converter, which is what the switched model is for.

**The cross-check has now found three defects the averaged model could not show:**

1. **A duty feedforward that silently cancelled the current loop.** `d_ff = 1 − V_rect/V_dc` looks
   standard, but with a stiff bus the boost already forces `V_rect = (1−d)·V_dc` in steady state, so
   the feedforward is satisfied at *every* operating point and exactly cancels whatever the PI does.
   The averaged model hid it by happening to converge near the right answer anyway.
2. **Current sampling read the ripple minimum, not the mean.** Sampling once per switching period at
   a fixed carrier phase biased the measured current low by half the ripple, so the loop drove the
   true current ~18% above reference. Fixed with a centre-aligned (triangular) carrier, where the
   inductor current at the carrier peak equals its average. This is invisible in an averaged model
   by construction.
3. **(Found by the rescale.) The boost diode was at Simscape's default 0.3 Ω on-resistance.** At
   4.7 A that is 1.4 V and 7 W — invisible. At 45 A it is 13 V and 600 W, 2% of the rating, and it
   would have appeared in this table as a switched-vs-averaged gap that is not real. Every
   semiconductor now reads one parameter, `wp.Ron_dev` (1 mΩ), so the bridge, boost diode and IGBT
   cannot disagree. The lesson is general: a default that is negligible at one rating is a
   measurement error at another, and the only defence is that *no* block keeps a default.

## 6. Feeds into my W7–W9 test scenarios

- Step 8 → 12 m/s; ramp; IEC extreme operating gust; cut-in / cut-out transitions
- Turbulent wind: sum-of-sines about a Weibull mean
- **Worst-case combined:** PV irradiance step down at the same instant as a wind gust up. Under DC
  coupling this was the largest DC-link excursion. Under AC coupling each source's DC link sees only
  its own transient — so the 5% / 200 ms criterion is tested per link by the single-source
  scenarios above — and the combined case becomes a **PCC event**: the largest swing in net export
  the two inverters can produce together, which is the real test of stability at SCR = 3 and of
  whether two SFS loops on one PCC help or hinder each other.

## 6a. What is built, and how to run it

```
models/wind/
  windLib.slx        library: Aerodynamics + MPPT, shared by both models so they
                     cannot drift. Edit here, never in a copy.
  windPlantAvg.slx   averaged  - variable-step, ~15 s per 150 s run
  windPlantSw.slx    switched  - Simscape Electrical, fixed-step at Ts_power,
                     ~250x real time (a 0.2 s run takes ~50 s)
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

**Two things the rescale caught in the tooling, fixed 4 Sep 2026:**

- `windPlantAvg`'s MPPT block was an *unlinked copy* of the library block, not a link, and it
  still carried the duty feedforward that defect 1 above removed. The averaged model was therefore
  running a different controller from the switched one — the exact drift the library exists to
  prevent. It is a library link again; both models now run the same MPPT code.
- `wind_mppt_sweep.m` never forced P&O mode. After the default moved to torque control, every
  point of its "open-loop duty sweep" was the torque controller finding the same operating point,
  and every cell of its "P&O tuning table" was the torque controller too. It now overrides
  `mppt_mode = 0` explicitly. The numbers in `windParams.m` are from the corrected script.

**Toolbox note.** This does *not* need Specialized Power Systems, and that is just as well:
`powerlib` is not installed on the lab image. The switched model is built from foundation
Simscape Electrical (`ee_lib`), which is present.

## 7. Open questions

1. **Hoang — DC link 2.** Agree that the wind branch's contract is unchanged (`i_dc` + telemetry
   into DC link 2, C_dc2 owned by integration), and that DC link 2 is 700 V like DC link 1?
2. **Aqib / Duc — inverter 2.** One inverter design instantiated twice (5 kW and 30 kW), or two
   designs? Same DC-link-loop bandwidth on both? The wind branch only needs "700 V, regulated".
3. **Redhwan — two SFS on one PCC.** Two inverters each pushing frequency the same way should make
   islanding *easier* to detect, but the NDZ analysis was done for one. Does it need redoing for the
   parallel case, and does the 30 kW inverter dominate it?
4. **Everyone — 30 kW sizing assumptions.** 12 m/s rated / 4 m/s cut-in give a 9.1 m rotor at
   203 rpm. Real 30 kW machines are 13.5–15.6 m rated at 9–11 m/s (table in §3). Rating at 10 m/s
   gives 12 m / 129 rpm and lands inside that range. Do we re-rate, or keep 12 m/s and say so? Either
   is one line in `windParams.m`; the harness re-runs in about half an hour.
5. Belal — the PV branch still uses the same boost topology and the same P&O, so we share one
   implementation across both DC links?
6. **Everyone — the MPPT default is optimal torque control, not P&O.** Section 2 has the
   measurements. P&O is still there as `wp.mppt_mode = 0`. This changes what we can claim about
   sharing one algorithm with PV, so it needs a decision rather than my say-so.
7. Belal — does the PV branch's P&O show the same ramp defect? Mine does, and the mechanism is
   general. Worth pointing the PV harness at a sustained irradiance ramp specifically.
