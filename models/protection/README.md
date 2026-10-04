# Protection branch — SFS anti-islanding + NDZ

Owner: S M Redhwan Ahmed · criterion **SC5** (islanding detected and disconnected
within 2 s), `docs/traceability.md`

**Status: SC5 met in the single-phase equivalent.** The detection chain is closed and
measured. At the test condition the standard specifies — matched RLC load, Qf = 1 —
Sandia Frequency Shift detects the island and disconnects in **198 ms** against a 2 s
budget, and the non-detection zone is empty across ±50% reactive mismatch. The one
item still open is the three-phase interface; see [Remaining](#remaining).

## Files

| file | purpose |
|---|---|
| `protectionParams.m` | single source of truth — every rating derives from `pp.S_plant` |
| `rlcTestLoad.m` | (ΔP, ΔQ) → R, L, C for the NDZ sweep, holding Qf constant |
| `SFS.slx` | **the rig** — inverter, RLC test load, grid, breaker, estimator, trip logic |
| `SFS_test1.slx` | predecessor, kept as the verified record behind the Week 7–8 figures |
| `protection_figures.m` | regenerates fig1–fig4 (phase reset, spectrum, island event, frequency) |
| `make_fig5.m` | regenerates fig5, the SFS on/off comparison — the headline SC5 evidence |
| `ndz_sweep.m` | runs the (ΔQ × Qf) sweep into `results/ndz_sweep.mat` |
| `ndz_plot.m` | draws fig6, the non-detection zone, from that `.mat` |
| `buildProtectionLib.m` → `protectionLib.slx` | **the reusable relay block** — what integration links to |
| `pll_startup_probe.m` | measures how long the SRF-PLL startup excursion leaves the trip band |
| `pll_jump_probe.m` | measures the same for a phase jump — sets the pickup delay |
| `design-record.md` | **every design choice, its justification and its source** — written for assembling the report |

```matlab
addpath(genpath('models'));
pp = protectionParams();     % parameters only, no Simulink
protection_figures           % fig1-fig4
make_fig5                    % fig5  - the SC5 headline
ndz_sweep(1:2); ndz_plot     % fig6  - run the sweep in chunks, see below
```

## How detection works

Five stages, each of which has to be present for the next to mean anything.

**1. The perturbation.** SFS advances the phase of the injected current relative to the
measured voltage by a *chopping factor* `cf`, where the advance is `θ = (π/2)·cf`. So
`cf` is the fraction of a quarter-cycle: `cf = 0.05` is 4.5°. Grid-connected this does
nothing observable, because the grid holds the frequency and simply absorbs the small
phase error. That is the point — the scheme must be invisible until the grid goes away.

**2. The positive feedback.** `cf = cf0 + kSFS·Δf`, where `Δf` is the measured
departure from 50 Hz. Once islanded, the phase advance pushes the frequency, the
frequency increase raises `cf`, and the larger `cf` pushes harder. The loop runs away.

**3. Why the load cannot stop it.** A parallel RLC load supplies phase
`θ_load(f) = arctan[Qf·(f/f_res − f_res/f)]`. Near resonance its slope is `2Qf/f₀`
rad/Hz. The SFS demand grows at `(π/2)·kSFS` rad/Hz. Detection requires the demand to
outgrow the supply:

```
kSFS > 4*Qf/(pi*f_n)       = 0.0255 at Qf = 1, f_n = 50 Hz
pp.kSFS = 0.05             ~2x margin
```

Below that ratio the two curves cross and the frequency settles at an equilibrium
instead of running away. **The gain condition is the runaway threshold, not the
detection limit** — see the sweep result below, which measures the difference.

**4. The estimate.** `FreqEstimator` recovers frequency at the PCC per cycle: zero
cross → period measure (triggered, clock minus unit delay) → reciprocal → clamp to
45–55 Hz. Without it `Δf` is identically zero and stage 2 never engages. It is a
standalone estimator because the SRF-PLL on the control branch is still a stub
(`GridAngle_ideal`).

**5. The relay.** `TripLogic` compares the estimate against 47 / 52 Hz and ORs the two,
then applies two guards before latching:

```
out_of_band = (f >= f_max) OR (f <= f_min)
armed       = t >= t_arm                      blocking:   is the estimate valid yet?
cond        = out_of_band AND armed
elapsed     = how long cond has held, reset the moment it clears
trip        = LATCH(elapsed >= t_pickup)      persistence: is this real?
```

`TripGate` then forces the current reference to zero. The gate sits *before*
`ctrl_delay`, not after, or it closes an algebraic loop.

**Both guards are measured, not guessed.** A bare comparator latches the instant the
estimate leaves the band, and the estimate is not trustworthy at every instant:

- **At startup** the SRF-PLL has to acquire lock, and while it does the frequency
  estimate is meaningless. Worst case measured at a 270° initial phase, where the loop
  slews almost a full turn: **170 ms outside 47–52 Hz**, pinned to the clamp rails at
  40 and 60 Hz. `t_arm` = 0.5 s blocks the relay until well past this. Run
  `pll_startup_probe` to reproduce. This was found by integration, not here — the rig's
  own zero-crossing estimator does not have an acquisition transient, so the fault only
  appears once the relay is fed the real PLL.
- **During a disturbance the plant must ride through.** A 30° phase jump — the SC4
  stimulus — drives the estimate to 60 Hz for **12.4 ms**, and a 60° jump for 20.7 ms.
  Without persistence the anti-islanding relay would trip on a grid event the PLL is
  specified to recover from. `t_pickup` = 0.1 s gives roughly 5× margin. Run
  `pll_jump_probe` to reproduce.

The cost is one `t_pickup` added to every detection: 98 ms becomes 198 ms, which is
still 10× inside the 2 s criterion. The benefit is that the relay no longer fires on
either of the two transients above.

## Results

### SC5 — detection at the standard test condition

| quantity | value |
|---|---|
| detection time, matched load (ΔP = ΔQ = 0, Qf = 1) | **198.1 ms** |
| criterion | 2.0 s |
| margin | 10× |
| PCC voltage change on islanding | **−2.72%** |
| current THD at rated output | 0.60% |
| fundamental | 306.23 A pk against `pp.Ipvmax` = 306.19 A |

The −2.72% voltage change is why this needs an active scheme. The matched load draws
almost exactly what the inverter supplies, so nothing moves far enough for
under/over-voltage protection to see it. `fig5` shows the same case with SFS disabled:
the frequency settles and never trips.

### The non-detection zone

77 points, ΔQ ∈ [−0.5, +0.5] in 11 steps × Qf ∈ {0.5 … 3.5} in 7 steps. **71 detected,
6 not.** Detection times 118.5–391.8 ms. Re-run 2026-10-04 with the relay delays in place.

| Qf | detected | detection time |
|---|---|---|
| 0.5 | 11/11 | 118.6–197.4 ms |
| **1.0** | **11/11** | **118.5–198.1 ms** |
| 1.5 | 11/11 | 118.7–237.1 ms |
| 2.0 | 11/11 | 118.8–334.9 ms |
| 2.5 | 10/11 | 118.9–391.8 ms |
| 3.0 | 9/11 | 119.0–226.3 ms |
| 3.5 | 8/11 | 119.1–255.4 ms |

**At Qf = 1 the non-detection zone is empty** across the full ±50% reactive range, so
SC5 is unaffected. All six failures sit at Qf ≥ 2.5, well above the test condition, and
at ΔQ between −0.2 and 0 — the detuning that most nearly cancels the phase SFS demands.

The persistence delay cost one case, Qf = 3.5 / ΔQ = −0.2, which the earlier sweep
detected at 591.5 ms. That case does not run away: the frequency falls and then
oscillates, dipping below 47 Hz for 85.1 ms every ~340 ms. The old relay latched on the
first dip; the new one needs 100 ms and never confirms. Tripping on an 85 ms dip is
exactly what a persistence delay exists to prevent, so this is the relay working — but
it is an honest cost, and it is recorded in `design-record.md` with the trade-off.

**ΔP is deliberately not swept.** `θ_load` depends only on Qf and the ratio `f/f_res`,
so real-power mismatch moves the resistance and therefore the voltage, but leaves the
resonant frequency and the phase slope untouched. It cannot affect frequency-based
detection. Sweeping it would have produced 121 points of which 110 were redundant.

### Why failure begins near Qf ≈ 2, not at the gain condition

The analytical threshold `Qf_crit = kSFS*pi*f_n/4 = 1.96` marks where *runaway* stops,
not where *detection* stops. Above it the frequency still travels — toward an
equilibrium rather than without bound — and trips whenever that journey crosses a
threshold in time. With `df_eq = (pi/2)*cf0 / [(2*Qf/f0) − (pi/2)*kSFS]`:

| Qf | denominator | f_eq | outcome |
|---|---|---|---|
| 1.0 | −0.0385 | none | no equilibrium — runaway, detected |
| 1.5 | −0.0185 | none | no equilibrium — runaway, detected |
| 2.0 | +0.0015 | 103.8 Hz | equilibrium exists but is far outside the band — detected |
| 2.5 | +0.0215 | 53.7 Hz | past 52 Hz, but not reached within 2 s — **temporal failure** |
| 3.0 | +0.0415 | 51.9 Hz | lands inside 47–52 — **geometric failure** |
| 3.5 | +0.0615 | 51.3 Hz | lands inside 47–52 — **geometric failure** |

A negative denominator means no solution exists: SFS outgrows the load at every
frequency. That is the regime Qf = 1 is in, and it is why the test condition the
standard specifies is comfortable rather than marginal. **Qf = 1 does not produce a
useful equilibrium — it produces none, which is better.**

So there are two distinct failure modes, and they are not interchangeable. Raising
`kSFS` cures the geometric one by pushing the equilibrium out of the band; it cures
the temporal one only incidentally, by making the approach faster.

## For integration — using the relay

**The rig is not what integration needs.** `SFS.slx` carries its own grid source,
breaker and RLC test load, none of which belong in the integrated plant. What
integration needs is the relay, and that is published as a library block:

```matlab
addpath(genpath('models'));
buildProtectionLib            % regenerates protectionLib.slx from source
% then drag protectionLib/AntiIslandingRelay into the model
```

```
AntiIslandingRelay
  in   f_hz   Hz   frequency estimate at the PCC
  out  trip   -    latches 1, stays 1

  mask f_min    47      Hz   under-frequency trip
       f_max    52      Hz   over-frequency trip
       t_arm    0.5     s    relay blocked before this
       t_pickup 0.1     s    out-of-band must persist this long
       Ts       1e-4    s    persistence timer rate
```

Defaults are numeric and self-contained, so the block works in a model that has never
heard of `protectionParams`. `SFS.slx` links to this same block and drives the mask from
`pp.*`, so the rig and the integrated model cannot drift apart — edit
`buildProtectionLib.m` and re-run, never the library by hand.

**Wiring it in:**

| | |
|---|---|
| **`f_hz` ←** | `srfPllLib/SRF_PLL` output 2. No estimator of your own is needed; the PLL's estimate is continuous rather than once-per-cycle, so it is better than the rig's. Its ±10 Hz clamp (40–60 Hz) sits comfortably outside the 47–52 band |
| **`trip` →** | the inverter's `enable`, once Duc adds one. Until then, a switch that forces `Id_ref` and `Iq_ref` to zero. That switch has to sit between the DC-link voltage loop and the inverter's `Id_ref` inport, because the DC-link loop is what normally drives it |

**Raise `t_arm` for the integrated model.** 0.5 s is sized for the rig, where the only
startup transient is the PLL acquiring lock — measured at up to 170 ms. The integrated
plant also has the DC bus charging and the LCL filter settling, neither of which has
been measured here. Set it past the point where the bus voltage and PCC voltage have
settled, and confirm `trip` is 0 through startup before trusting anything downstream.

**The latch is permanent.** Once `trip` goes high it stays high for the rest of the run;
there is no reconnection path. AS/NZS 4777.2 requires reconnection after 60 s within
limits, which is not implemented — see [Remaining](#remaining).

## Single-phase equivalent

The model is **one phase of the three-phase plant**, so the 150 kVA nameplate is
divided by three. Using the plant rating directly would overstate current by 3×.

This is exact rather than approximate for a balanced three-phase system, and the NDZ
result transfers without rescaling: every axis is a normalised ratio (ΔQ per unit of
`P_inv`, and Qf, which is dimensionless), so the factor of three cancels in both.

Shared quantities are cross-checked against `models/inverter/invParams.m` and agree
by construction, not by coincidence:

| | protection | inverter | |
|---|---|---|---|
| rated current | `pp.Ipvmax` = 306.2 A pk | `ip.I_pk` = 306.2 A pk | agrees |
| grid voltage | `pp.Vg_amp` = 326.6 V pk | `ip.V_grid_pk` = 326.6 V pk | agrees |
| control rate | `pp.Ts` = 1e-4 s | `ip.Ts_ctrl` = 1e-4 s | agrees |
| filter capacitance | `pp.Cf` = 44.8 µF | `ip.Cf` = 44.8 µF | agrees |

## The test load, and why the site load is absent

`rlcTestLoad.m` builds a parallel RLC resonant at 50 Hz with quality factor Qf,
matched to the inverter output. The LCL filter capacitor `pp.Cf` sits electrically at
the PCC and is part of what the island sees, so the bank carries `C_tot − Cf` rather
than ignoring it.

The 250 kW site load is **disconnected** during the islanding test. With it present
the island has a large power deficit, the voltage collapses, and undervoltage
protection detects the island trivially — which would prove nothing about SFS. The
matched load is the worst case, and it is the case the standard specifies.

The inductor is given an initial current (`pp.iL0`). A lossless inductor energised at
t = 0 keeps its startup DC component forever, because nothing in that branch
dissipates it. The fix is the initial condition and **not** winding resistance, which
would remove the offset equally but reduce Qf and so invalidate the test load the
whole NDZ analysis rests on.

## Running the sweep

A point that fails runs the full stop time and is roughly ten times slower than one
that trips early, so the full 77-point sweep takes the best part of an hour. It
checkpoints after every point and takes a row index, so run it in chunks:

```matlab
ndz_sweep(1:2)     % Qf = 0.5, 1.0
ndz_sweep(3:4)     % resumes, appends
ndz_plot           % draws whatever is complete, warns if not all
```

Changing `dQ_grid` or `Qf_grid` is refused against stored results — delete
`results/ndz_sweep.mat` first, deliberately.

## Remaining

1. **Three-phase interface.** Everything above is the single-phase equivalent. In the
   dq-frame controller SFS enters as a quadrature-current reference,
   `Iq_ref = Id_ref*tan(theta)`, not as a generated waveform. The inverter README
   lists **"Who owns `Iq_ref`?"** as unassigned — that is this interface, and it needs
   claiming before SC5 can be demonstrated on the full plant.
2. **Automatic reconnection.** AS/NZS 4777.2 requires reconnection once voltage and
   frequency have been within range for a sustained period. The latch is currently
   permanent, so the rig disconnects and stays disconnected. Scope confirmation
   pending with the product owner.
3. **Verification against the standards**, all flagged in the source:
   - 47 / 52 Hz thresholds against the AS/NZS 4777.2 table — currently asserted
   - the gain condition against IEEE 1547.1 — note that the sweep independently
     measures the runaway boundary between Qf 2.0 and 2.5 against a predicted 1.96
   - whether the frequency drift rate scales with `pp.Ts`, which would make 98 ms
     partly an artefact of the 10 kHz control rate
   - SC5 test wording with Hoang — integration owns whether the site load is present

## Design notes

**Drive frequency up, not down.** The trip thresholds are asymmetric — 52 Hz is 2 Hz
above nominal, 47 Hz is 3 Hz below — so an upward drift reaches its threshold about a
third sooner. A positive `cf0` is therefore the better choice for detection speed.

**Chopping factor is bounded** at `pp.cf_max` = 0.5, i.e. ±45°. Under runaway it would
otherwise grow without limit, and beyond a quarter-cycle the shift stops being a
perturbation and real power export collapses. It never engages in normal operation
(`cf` = `cf0` = 0.05) nor during a normal runaway (`cf` reaches 0.30 at the ±5 Hz
clamp inside the estimator), so if this limit is ever active something upstream is
wrong.

**One control-cycle delay is load-bearing.** `ctrl_delay` applies the SFS current
reference one cycle after the voltage that produced it, as a real DSP would. Without
it the injected current and the PCC voltage it produces form an algebraic loop.

**Figures are theme-proof by construction.** Every figure script sets colours
explicitly, builds the figure invisible with `InvertHardcopy` off, and exports on a
white background. Do **not** add a call to `theme()` — it can block the session for
the full timeout when driven non-interactively.
