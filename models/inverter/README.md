# Inverter branch — dq current loop + SVPWM + LCL filter

**Grid current THD at rated output: 1.42 %** against the < 5 % criterion.

Three models, one parameter file:

| model | what it is |
|---|---|
| `invPlantAvg` | **averaged** — current loop + ideal modulator + LCL + grid. Where the loop is tuned. |
| `invPlantSw` | **switched** — current loop + SVPWM + IGBT bridge + LCL + grid. Where THD is measured. |
| `invBridge120` | the earlier 120° six-step topology validation, kept as evidence. |

Owner: Duc Pham

## Files

| file | purpose |
|---|---|
| `invParams.m` | single source of truth — every model reads from here |
| `buildInvLib.m` → `invLib.slx` | shared blocks, **locked**; models link, never copy |
| `buildInvPlantAvg.m` / `buildInvPlantSw.m` / `buildInvBridge120.m` | model builders |
| `invSim.m` | runs any of the three, returns the telemetry bus |
| `inv_model_check.m` | sizing, loop and filter arithmetic — no Simulink, no toolbox |
| `inv_model_lint.m` | 24 structural checks across the three models |
| `inv_current_loop_check.m` | step response vs the graded spec |
| `inv_grid_thd_check.m` | **the THD criterion** |
| `inv_thd_check.m` | six-step spectrum vs closed form (`invBridge120`) |

```matlab
addpath(genpath('models'));
inv_model_check          % arithmetic only
inv_model_lint           % 24/24 structural checks
inv_current_loop_check   % settling / overshoot / cross-coupling
inv_grid_thd_check       % grid current THD at rated output
```

`invLib` holds `CurrentLoop`, `Modulator_SVPWM` and `LCLFilter`. Both fidelities
link the same blocks, so they cannot drift apart — the lint checks the links are
resolved.

## The LCL filter

| | value | why |
|---|---|---|
| L1 | 0.254 mH | 15 % ripple (45.9 A pk-pk) on the inverter side |
| Cf | 44.8 µF | 1.5 % of base → 2.25 kVAr, 1.5 % of rating |
| Rd | 0.459 Ω | passive damping, ⅓ of Cf's impedance at resonance |
| L2 | 0.127 mH | L2/L1 = 0.5 |
| f_res | 2585 Hz | 5.2× above the fundamental band, 1.9× below f_sw/2, 5.2× above the loop bandwidth |
| attenuation | 14× | at f_sw, vs a plain L of the same total inductance |

**What actually sized it was the current loop, not ripple or attenuation.** The
bridge makes 404 V peak; the grid takes 326.6 V of that standing still; only
**77.5 V** is left to move current with. That caps di/dt, and the 2 ms settling
spec therefore caps the *total* inductance at 0.507 mH. At 0.381 mH there is
25 % margin. More inductance would filter better and miss the settling spec.

## Results

**THD at rated output** (`inv_grid_thd_check`, switched model, dead time modelled):

| | inverter i1 | grid i2 |
|---|---|---|
| fundamental | 302.4 A pk | 302.7 A pk |
| THD (≤ 50th) | 1.26 % | 1.31 % |
| **THD (total, to Nyquist)** | 3.14 % | **1.42 %** |

Where the distortion sits, as % of fundamental:

| order | freq | i1 | i2 | |
|---|---|---|---|---|
| 5 | 250 Hz | 0.95 | 0.96 | dead time — **filter does nothing** |
| 7 | 350 Hz | 0.69 | 0.71 | dead time — **filter does nothing** |
| 198 | 9.9 kHz | 1.33 | 0.10 | switching — **13× attenuation** |
| 202 | 10.1 kHz | 1.34 | 0.10 | switching — **13× attenuation** |

That table is the whole story of the filter. It removes the switching
sidebands by 13× (design predicted 14×) and leaves the low-order content
untouched, because 250 Hz is far below the 2585 Hz corner. The 5th and 7th come
from **dead time**, and what suppresses them is the current loop, not the
filter — they sit inside its 500 Hz bandwidth.

**Current loop** (`inv_current_loop_check`, averaged model, now with the real
LCL and its resonance in the plant):

| scenario | settling | overshoot | residual |
|---|---|---|---|
| Id 0 → 50 % rated | 1.20 ms | 1.2 % | −0.04 % |
| Id 50 % → 100 % | 1.20 ms | 1.1 % | −0.11 % |
| Iq 0 → 25 % rated | 0.90 ms | 2.0 % | −0.58 % |
| Iq step, watching Id | — | — | 1.07 % cross-coupling |

Spec is settling < 2 ms, overshoot < 10 %. Met, and the loop does not excite the
filter resonance.

## Three findings that affect other people's work

**1. Dead time is the THD floor, not the filter.** Once the LCL has done its
job, 1.3 of the 1.42 % is dead time producing 5th and 7th harmonics. Halving
`ip.t_dead` roughly halves that. Belal should treat dead time as a design
parameter with a THD cost, not a hardware afterthought — and it is the first
thing to revisit if the number ever needs to come down.

**2. The DC bus must float.** Grounding the DC negative *and* the grid neutral
puts the bridge's Vdc/2 common-mode offset across the filter inductors' 5 mΩ —
a DC short. First build of the switched model drew 35 kA. A transformerless
grid-tie DC bus floats; the grid neutral is the single reference. Relevant to
Hoang when the branches are joined at the shared bus.

**3. The `ee_lib` three-phase source ships with a 1 MVA short-circuit level.**
SCR 6.7 at 150 kVA — a weak grid nobody asked for, and it destabilises the
current loop through the PCC voltage feedforward. `ip.grid_Z_opt` sets it
explicitly (0 for tuning, 1 for the SCR sweep).

## Checked against Belal's PV model (9 Sep)

`models/pv/solarsimulink.slx` landed after this branch was built, so every
shared number was re-read out of his model rather than assumed. **Nothing in
`invParams.m` changes.**

| interface | inverter | Belal's PV | |
|---|---|---|---|
| DC bus | `ip.V_dc` = 700 V | `Rload_placeholder` = 4.08 Ω → 700 V at 120 kW | agrees |
| switching frequency | `ip.f_sw` = 10 kHz | PWM carrier `[0 1e-4]` → 10 kHz | agrees |
| array rating | — | 723s × 48p, ≈360 V / 330 A ≈ 120 kW at STC | matches the 120 kWp in the root README |
| boost duty at MPP | — | 1 − 360/700 = 0.49 | mid-range, well inside the P&O 0.05–0.95 clamp |

The PV boost runs into a placeholder resistor, not the shared bus — Belal's own
figure annotates it *"Real 700 V bus = inverter's job"*. So the two models do
not yet meet electrically and there is no bus-regulation conflict to resolve;
the join happens in Hoang's integration model, and the loop that holds 700 V is
the DC-link loop, not this branch.

**One thing the team should look at.** 120 kWp PV + 60 kW wind is 180 kW into a
150 kVA inverter — a DC/AC ratio of 1.2. `docs/decisions.md` records that as
deliberate ("PV and wind do not peak together"), so it is not a defect, but it
does mean the inverter clips when they *do* coincide, and nothing currently
tests that. `ip.I_pk` = 306.2 A peak (216.5 A rms, 214 A on the DC side) is the
limit that would engage. Note that `TestHarness/config/harnessParams.m` sets
`P.ctrl.Imax` = 400 A — about 1.9× the inverter's actual DC-side rating — so the
harness as configured would never exercise the clip. Hoang's call.

## Open items

- **Who owns `Iq_ref`?** Held at 0 (unity power factor). AS/NZS 4777.2 has
  power-factor requirements and nobody has that task.
- **Circular voltage limiter.** The PI is limited per axis, so a full-rated step
  briefly asks ~4 % more than the bridge can make. The proper fix is a |V_dq|
  limiter in the **modulator**, which is the only block that knows the ceiling.
- **`Modulator_SVPWM` is a stub.** It is a correct SVPWM (min-max zero-sequence
  injection, carrier comparison, dead time) built so the filter could be
  verified end to end. Belal's block replaces it; the THD number moves with it.
- **`GridAngle_ideal` is a stub** for Aqib's SRF-PLL — dynamics-free by design.
- **Folder placement — settled.** This lives in `models/inverter/`, and the root
  README's layout now lists it. `models/control/` is Aqib's SRF-PLL and DC-link
  loop.

## Things worth knowing before extending this

- **`CurrentLoop` has no direct feedthrough on any output.** Every output is
  behind a one-sample delay — the real computation latency — so the block drops
  into any model without creating an algebraic loop through the plant.
- **`CurrentLoop` is virtual, not atomic.** An atomic subsystem reports direct
  feedthrough on *every* output if *any* path has it, which re-creates the
  algebraic loop despite the delays.
- **Solver step is 0.5 µs**, not the wind branch's 1 µs: at f_sw = 10 kHz the
  solver step is also the PWM edge resolution, and 1 µs quantises the duty to
  1 %, which shows up in a THD measurement as a simulation artefact.
- **Specialized Power Systems is not installed**, as the root README warns.
  Everything here is foundation Simscape Electrical (`ee_lib`).

## Next

1. **SVPWM** — Belal's block replaces `Modulator_SVPWM`. Re-run
   `inv_grid_thd_check`; the number moves with dead time.
2. **SRF-PLL** — Aqib's block replaces `GridAngle_ideal`.
3. **DC-link voltage loop** feeding `Id_ref` — Aqib.
4. **SCR sweep** — set `ip.grid_Z_opt = 1`, `ip.SCR = 3`, and re-run both the
   loop check and the THD check. Expect both to degrade; that is the point of
   the criterion.
