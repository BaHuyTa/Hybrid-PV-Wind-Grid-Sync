# Protection branch — SFS anti-islanding + NDZ

Owner: S M Redhwan Ahmed · criterion **SC5** (islanding detected and disconnected
within 2 s), `docs/traceability.md`

**Status: rig built and verified, detection not yet closed.** The circuit, the test
load and the SFS control law are in place and behave correctly. The positive-feedback
loop is not yet closed — see [Remaining](#remaining).

## Files

| file | purpose |
|---|---|
| `protectionParams.m` | single source of truth — every rating derives from `pp.S_plant` |
| `rlcTestLoad.m` | (ΔP, ΔQ) → R, L, C for the NDZ sweep, holding Qf constant |
| `SFS_test1.slx` | single-phase islanding rig: inverter, RLC test load, grid, breaker |
| `protection_figures.m` | regenerates the evidence figures into `results/` |

```matlab
addpath(genpath('models'));
pp = protectionParams();     % parameters only, no Simulink
protection_figures           % runs the model, writes three figures
```

## Single-phase equivalent

The model is **one phase of the three-phase plant**, so the 150 kVA nameplate is
divided by three. Using the plant rating directly would overstate current by 3×.

Shared quantities are cross-checked against `models/inverter/invParams.m` and agree
by construction, not by coincidence:

| | protection | inverter | |
|---|---|---|---|
| rated current | `pp.Ipvmax` = 306.2 A pk | `ip.I_pk` = 306.2 A pk | agrees |
| grid voltage | `pp.Vg_amp` = 326.6 V pk | `ip.V_grid_pk` = 326.6 V pk | agrees |
| control rate | `pp.Ts` = 1e-4 s | `ip.Ts_ctrl` = 1e-4 s | agrees |
| filter capacitance | `pp.Cf` = 44.8 µF | `ip.Cf` = 44.8 µF | agrees |

## The test load, and why the site load is absent

The islanding test uses the **RLC test load alone**, matched to inverter output and
resonant at 50 Hz with Qf = 1. The 250 kW site load is deliberately **not** connected.

That is not an oversight. With 250 kW of demand against 150 kVA of generation, opening
the breaker leaves a 100 kW deficit; the PCC voltage collapses to roughly 60–77 % of
nominal within a cycle and plain undervoltage protection trips immediately. The test
would pass while proving nothing, because the anti-islanding scheme never has to act.

The non-detection zone exists precisely where generation ≈ load, so that opening the
breaker changes nothing measurable. That is the case the standard specifies, and the
only one worth measuring. `docs/traceability.md` currently reads as though both loads
are present for SC5 — that wording needs settling with integration.

The inverter's LCL filter capacitor sits electrically at the PCC and is part of what
the island sees, so the RLC bank is trimmed by `pp.Cf` and bank + filter together
give the resonance the standard requires.

## Modelling decisions

**The inverter is a controlled current source, not a switching bridge.** Justified by
bandwidth separation: the measured current loop settles in 1.20 ms
(`inv_current_loop_check`) against islanding dynamics of hundreds of milliseconds, so
the loop is effectively instantaneous at this timescale. Same reasoning the team uses
to justify tuning the cascade inside-out.

**One control-cycle delay on the current reference.** Without it the injected current
and the PCC voltage it produces form an algebraic loop. The delay is not a numerical
patch — a real DSP samples, computes, and applies on the following cycle. The
inverter branch's `CurrentLoop` uses the same one-sample delay for the same reason.

**The breaker interrupts immediately, not at current zero.** `zeroCrossingEnable`
waits for current within `i_th` = 1e-8 A, which the solver never samples — the
internal state flips while current keeps flowing. Immediate interruption also makes
the island instant exactly `pp.t_island`, so detection time is measured from a
defined origin.

**The test-load inductor starts in steady state** (`pp.iL0`). A lossless inductor
energised at t = 0 keeps its startup DC component forever. Adding winding resistance
would remove it but also add loss to the reactive branch, changing Qf and
invalidating the test load — so the initial current is set instead.

**Foundation Simscape Electrical only.** Specialized Power Systems is not installed,
so there is no `powergui`, no three-phase source/breaker/RLC blocks, and no FFT
Analysis tool. Harmonic analysis is done in code.

## Verified

Grid-connected steady state, and the island at `pp.t_island` = 1.0 s:

| | value | |
|---|---|---|
| inverter current peak | 306.15 A | matches `pp.Ipvmax` |
| PCC voltage, grid-connected | 230.84 V rms | vs 230.94 nominal |
| grid current DC component | −0.00 A | inductor initial condition holds |
| grid current after island | 0.000 A | breaker isolates cleanly |
| injected current THD | 0.48 % | measured on uniformly resampled data |
| phase reference | resets every 19.96 ms | locked to PCC zero crossings |
| PCC frequency, islanded | 50.20 Hz | shifted off resonance by the SFS phase |

That last row is the mechanism working: with the phase reference locked, the SFS phase
advance forces the island off resonance. It settles rather than running away because
the feedback path is still open.

## Remaining

1. **`fpcc` is a constant placeholder.** Δf is therefore always zero and `cf` never
   leaves `cf0`, so there is no positive feedback. A frequency estimate at the PCC
   closes the loop. Aqib's SRF-PLL is still a stub (`GridAngle_ideal`), so this needs
   a standalone estimator for now.
2. **Trip logic does not exist.** Over/under-frequency comparison, a latch, and
   forcing the current reference to zero.
3. **Saturate `cf`** — under runaway feedback it grows without bound, and a phase
   advance beyond π/2 is meaningless.
4. **NDZ sweep** — `rlcTestLoad.m` is written and verified; the sweep over (ΔP, ΔQ)
   is the SC5 deliverable.
5. **Three-phase.** Possibly moot: in a dq-frame controller SFS enters as an angle
   offset or a quadrature-current injection, not as a generated waveform. The
   inverter README lists **"Who owns `Iq_ref`?"** as unassigned — that is this
   interface, and it should be claimed.

## Design notes

**Gain floor.** Detection needs the SFS phase-frequency slope to exceed the load's:
`kSFS > 4·Qf/(π·f_n)`, which is 0.0255 at Qf = 1 and 50 Hz. `pp.kSFS` = 0.05 gives
roughly 2× margin. Verify the derivation against IEEE 1547.1 before it goes in a
report.

**Drive frequency up, not down.** The trip thresholds are asymmetric — 52 Hz is 2 Hz
above nominal, 47 Hz is 3 Hz below — so an upward drift reaches its threshold about a
third sooner. A positive `cf0` is therefore the better choice for detection speed.
Confirm both thresholds against the AS/NZS 4777.2 table; they are currently unverified.
