# Protection — design record, validation and sources

Owner: S M Redhwan Ahmed · workstream: anti-islanding (SC5)

**Purpose.** Every design choice in the protection workstream, why it was made, and what
backs it. Written so that report sections can be assembled from here rather than
reconstructed from memory or chat history.

**How to read the Evidence column.**

| marker | meaning |
|---|---|
| **verified** | the source text was read directly and is quoted below |
| **derived** | follows analytically from quantities in `protectionParams.m`; the derivation is given |
| **measured** | produced by a script in this folder; the script and the number are named |
| **asserted** | believed correct, but not yet checked against a primary source — **do not cite in the report until confirmed** |

---

## 1. Which standards apply, and why

The plant is **150 kVA**, which sits under the 200 kVA ceiling of AS/NZS 4777.2:2020.
That was a deliberate sizing choice (`docs/decisions.md`): above it the project would fall
under NER generator performance standards — fault ride-through, reactive capability
curves — which are out of scope.

The chain of authority for anti-islanding runs:

```
AS/NZS 4777.2:2020  §4.3   active anti-islanding required
        |
        +-- compliance demonstrated by test to AS/NZS IEC 62116:2020
                                              (adoption of IEC 62116:2014)
```

So IEC 62116 defines the test, and that is the document most of the test-condition
decisions below point at.

**Relevant definitions, IEC 62116:2014 cl. 3** — useful wording for the report:

> **3.9 stopping signal** — "signal provided by the inverter indicating it has ceased energizing its utility grid-connected output terminals"
>
> **3.10 unintentional island** — "islanding condition in which the generation within the island that is supposed to cease energizing the utility grid instead continues to energize the utility grid"

---

## 2. Compliance targets

| # | Decision | Value | Why | Evidence |
|---|---|---|---|---|
| 1 | Over-frequency trip | **52 Hz** | AS/NZS 4777.2:2020, Australia A parameter set, for installations >30 kVA up to 200 kVA (3-phase) — our band at 150 kVA | **verified** — Jemena connection requirements table |
| 2 | Under-frequency trip | **47 Hz** | same table | **verified** — same |
| 3 | Maximum disconnection time | **2 s** | same table, both the frequency functions and "Active anti-islanding" carry 2 s | **verified** — same; this is SC5 |
| 4 | Reconnection delay | **60 s** | same table, "Reconnection Delay 60 s" | **verified** — same; **not yet implemented**, see §7 |
| 5 | Central protection relay | **out of scope** | above 30 kVA the network operator additionally requires a central relay (vector shift 20°, ROCOF 4 Hz/s, current unbalance 21.7 A). This is a *network connection* requirement, not AS/NZS 4777.2, and the project is a simulation of the inverter-side protection | **verified** that the requirement exists; the scope decision is ours |

**Note on the source.** The Jemena document is a distribution network operator's compliance
specification stating settings "aligned with AS4777.2:2020". It is an authoritative industry
source but **it is not the standard itself**. Before the report goes in, confirm §2.1–2.4
against a copy of AS/NZS 4777.2:2020 Table 4.1/4.2.

---

## 3. Test load and test conditions

| # | Decision | Why | Evidence |
|---|---|---|---|
| 6 | Parallel RLC load, resonant at 50 Hz, matched to inverter output | This is the specified test circuit | **verified** — IEC 62116 cl. 6.1: "The test uses an RLC load, resonant at the EUT nominal frequency (50 Hz or 60 Hz) and matched to the EUT output power" |
| 7 | Quality factor **Qf = 1** | Stated as the standard's test value | **asserted** — the definition of Qf is at IEC 62116 cl. 3.7, but the numeric test value was **not** in the public preview. Confirm against the full standard before citing |
| 8 | Load **balanced** across phases | The standard mandates it for multi-phase equipment — and this is what makes the single-phase equivalent exact rather than approximate | **verified** — IEC 62116 cl. 6.1: "For a multi-phase EUT, the load shall be balanced across all phases" |
| 9 | 250 kW **site load disconnected** during the islanding test | With it connected the island carries a large power deficit, voltage collapses, and undervoltage protection detects the island trivially — demonstrating nothing about SFS. The matched load is the worst case and the one specified | **derived** from #6; the standard's test circuit contains only the RLC load |
| 10 | Test at the **inverter terminals**, not on the integrated plant | The standard's test circuit is AC source → switch → RLC load → inverter. No PV, no wind, no DC bus, no site load | **verified** — IEC 62116 cl. 6.1: "The following test is designed for an EUT consisting of a single or multi-phase inverter" |
| 11 | LCL filter capacitor `Cf` counted as part of the load | `Cf` sits electrically at the PCC and is part of what the island sees. The standard specifies the *total* load resonant at `f_n` with quality factor Qf, so the RLC bank carries `C_tot − Cf` | **derived** — `protectionParams.m:55-70` |
| 12 | Inductor given an initial current, **not** winding resistance | A lossless inductor energised at t = 0 keeps its startup DC component forever. Adding winding resistance would remove it equally — but would reduce Qf and so invalidate the specified test load | **derived**; **measured**: DC component 306 A → 0.01 A, pre-island RMS 47.6 A → 7.8 A |

---

## 4. Single-phase equivalent, and why it is valid for a three-phase plant

**The claim.** The model is one phase of the three-phase plant. The 150 kVA nameplate is
divided by three (`pp.S_rated = pp.S_plant/pp.n_ph`). The NDZ result transfers to three
phases without rescaling.

**Why it holds — four legs:**

1. **The standard mandates a balanced load** (#8 above, verified quote). A balanced
   three-phase wye has zero neutral current, so each phase is an independent circuit with
   its own return. Per-phase equivalence is *exact* under this condition, not approximate —
   and the condition is imposed by the test, not assumed by us.

2. **The standard describes the three-phase test as the single-phase circuit replicated.**
   **verified** — IEC 62116 cl. 4 (Testing circuit): *"The testing circuit shown in Figure 1
   shall be employed. Similar circuits shall be used for three-phase output."*

3. **Commercial test equipment implements exactly that** — three independent per-phase RLC
   circuits, individually programmable (Action Power application note, §9).

4. **The physics.** The load's phase angle is `arctan[Qf·(f/f_res − f_res/f)]`, a per-phase
   quantity identical in all three phases under a balanced load. The SFS demand is identical
   in all three. So the frequency dynamics are identical. Both NDZ axes are dimensionless
   ratios — ΔQ per unit of `P_inv`, and Qf — so the factor of three cancels in both.

**The limit of the claim — state this before anyone asks.** The NDZ *boundary* transfers
exactly, because it is set by the phase-balance condition, which is per-phase. The detection
*times* do not transfer exactly, because two things differ:

- the rig's estimator updates **once per cycle** from zero crossings; a three-phase SRF-PLL
  estimates continuously, so detection would likely be **faster**
- the rig drives an ideal controlled current source with a one-sample delay; a real dq
  current loop has finite bandwidth (SC3: settling < 2 ms — fast relative to the ~20 ms
  frequency dynamics, so it should not move the boundary, but it is not literally zero)

Both differences point in our favour, which is a reason to volunteer them rather than wait.

---

## 5. SFS design and tuning

| # | Decision | Value | Why | Evidence |
|---|---|---|---|---|
| 13 | Base chopping factor `cf0` | 0.05 | 4.5° phase advance — large enough to drive the frequency, small enough to be a perturbation. `cf` is the fraction of a quarter-cycle: `θ = (π/2)·cf` | **derived** |
| 14 | Feedback gain `kSFS` | 0.05 | Detection needs the SFS phase-frequency slope to exceed the load's: `kSFS > 4·Qf/(π·f_n)` = 0.0255 at Qf = 1. 0.05 gives ~2× margin | **derived**; the *formula* is **asserted** pending a check against IEEE 1547.1 |
| 15 | `cf` bounded at ±0.5 | ±45° | Under runaway `cf` would grow without limit, and beyond a quarter-cycle the shift stops being a perturbation and real power export collapses. Never engages normally (`cf` = 0.05) nor in a normal runaway (`cf` reaches 0.30 at the estimator's ±5 Hz clamp), so if it is ever active something upstream is wrong | **derived** |
| 16 | Drive frequency **up**, not down | `cf0` positive | The thresholds are asymmetric — 52 Hz is 2 Hz above nominal, 47 Hz is 3 Hz below — so an upward drift reaches its threshold about a third sooner | **derived** from #1, #2 |
| 17 | ΔP **not** swept in the NDZ | — | `θ_load` depends only on Qf and the ratio `f/f_res`. Real-power mismatch moves the resistance and therefore the voltage, but leaves the resonant frequency and phase slope untouched, so it cannot affect frequency-based detection. Sweeping it would have produced 121 points of which 110 carried no new information | **derived** |
| 18 | One control-cycle delay on the current reference | `pp.Ts` = 1e-4 | Models a real DSP implementation, and is what makes the feedback path solvable — without it the injected current and the PCC voltage it produces form an algebraic loop. Matches `ip.Ts_ctrl` | **derived** |

### The gain condition is the *runaway* threshold, not the detection limit

This distinction is the most commonly misread part of the analysis and is worth a paragraph
in the report.

`Qf_crit = kSFS·π·f_n/4 = 1.96` marks where the frequency stops running away — not where
detection stops. Above it the frequency still travels, toward an equilibrium rather than
without bound, and trips whenever that journey crosses a threshold in time.

Equilibrium frequency: `Δf_eq = (π/2)·cf0 / [(2·Qf/f₀) − (π/2)·kSFS]`

| Qf | denominator | f_eq | outcome |
|---|---|---|---|
| 1.0 | −0.0385 | none | no equilibrium — runaway, detected |
| 1.5 | −0.0185 | none | no equilibrium — runaway, detected |
| 2.0 | +0.0015 | 103.8 Hz | equilibrium exists, far outside the band — detected |
| 2.5 | +0.0215 | 53.7 Hz | past 52 Hz but not reached within 2 s — **temporal failure** |
| 3.0 | +0.0415 | 51.9 Hz | lands inside 47–52 — **geometric failure** |
| 3.5 | +0.0615 | 51.3 Hz | lands inside 47–52 — **geometric failure** |

A negative denominator means **no solution exists**: SFS outgrows the load at every
frequency. That is the regime Qf = 1 is in. **Qf = 1 does not produce a useful equilibrium —
it produces none, which is better.** The standard's own test condition is therefore
comfortable rather than marginal, and that is a consequence of the gain choice at #14, not
of Qf.

Two distinct failure modes follow, and they are not interchangeable: raising `kSFS` cures
the geometric one by pushing the equilibrium out of the band, and cures the temporal one
only incidentally, by making the approach faster.

**Cross-check:** theory predicts the runaway boundary at Qf = 1.96; the sweep measured
detection complete through Qf = 2.0 and first failures at Qf = 2.5. Prediction and
measurement agree to within one grid step — an independent confirmation of #14.

---

## 6. Measured results

All from the scripts in this folder. Regenerate with `protection_figures`, `make_fig5`,
`ndz_sweep` + `ndz_plot`.

### SC5 headline

| quantity | value | source |
|---|---|---|
| Detection time, matched load (ΔP = ΔQ = 0, Qf = 1) | **98.0 ms** | `make_fig5` → `fig5` |
| Criterion | 2.0 s | AS/NZS 4777.2 (#3) |
| Margin | **20×** | |
| PCC voltage change on islanding | **−2.72%** | `protection_figures` → `fig3` |
| Current THD at rated output | **0.60%** | `protection_figures` → `fig2` |
| Fundamental current | 306.23 A pk vs `pp.Ipvmax` = 306.19 A | same |
| Frequency at trip | 52.03 Hz vs 52.0 threshold | `protection_figures` → `fig4` |

The **−2.72%** figure is the quantitative justification for an active scheme: the matched
load draws almost exactly what the inverter supplies, so no voltage or current magnitude
moves far enough for passive protection to act on. With SFS disabled the frequency settles
and never trips (`fig5`, left trace).

### Non-detection zone

77 points: ΔQ ∈ [−0.5, +0.5] × 11, Qf ∈ {0.5 … 3.5} × 7. **72 detected, 5 not.** Detection
times 18.4–591.5 ms.

| Qf | detected | detection time |
|---|---|---|
| 0.5 | 11/11 | 18.4–97.2 ms |
| **1.0** | **11/11** | **18.5–98.0 ms** |
| 1.5 | 11/11 | 18.6–137.1 ms |
| 2.0 | 11/11 | 18.7–234.8 ms |
| 2.5 | 10/11 | 18.8–291.7 ms |
| 3.0 | 9/11 | 18.9–125.5 ms |
| 3.5 | 9/11 | 19.0–591.5 ms |

**At the standard's Qf = 1 the non-detection zone is empty** across the full ±50% reactive
range. All five failures sit at Qf ≥ 2.5 and at ΔQ of 0 or −0.1 — the detuning that most
nearly cancels the phase SFS demands.

---

## 7. Open items

| item | status |
|---|---|
| **Qf = 1 numeric value** | **asserted** — confirm against the full AS/NZS IEC 62116:2020 text (#7) |
| **Gain condition vs IEEE 1547.1** | **asserted** — the formula `kSFS > 4Qf/(πf_n)` is used throughout; confirm the derivation. Note the sweep independently corroborates it (§5) |
| **Frequency thresholds vs the standard itself** | **verified** against a network operator document; confirm against AS/NZS 4777.2:2020 Table 4.1/4.2 directly |
| **Does drift rate scale with `pp.Ts`?** | unchecked. If it does, 98 ms is partly an artefact of the 10 kHz control rate. Testable: re-run `make_fig5` at `pp.Ts` = 5e-5 and 2e-4 |
| **Automatic reconnection (60 s)** | required (#4), not implemented. The latch is currently permanent. Scope confirmation pending with the product owner. Note it composes correctly with what exists: after a trip the current goes to zero and the PCC voltage collapses, so the reconnect timer can never start while the island is live — it is not possible to reconnect into an island |
| **Three-phase demonstration** | §4 defends the result analytically. Physical integration depends on the `Iq_ref` interface, §8 |

---

## 8. Integration interfaces

Verified against Duc's build scripts and Aqib's PLL library on 2026-10-03.

| interface | state | owner |
|---|---|---|
| `Iq_ref` — SFS perturbation input | **exists and is drivable.** Genuine inport on `invPlantAvg` (Port 2) and `invPlantSw` (Port 3), tracked by `Vq = PI(Iq_ref − Iq) + Vgq + ωL·Id`. `ip.Iq_ref = 0` is a default value, not a hardwire | Duc — **contested**, see below |
| `f_hz` — frequency estimate | **exists.** `srfPllLib/SRF_PLL` outputs `theta`, `f_hz`, `vd`; mask `Ts` = 1e-4 (matches `pp.Ts`), `f0` = 50, `fbw` = 25, `zeta` = 0.707. Clamped to 50 ± 10 Hz, so the 47/52 band sits inside it | Aqib — available, no action needed |
| `enable` — stopping signal | **missing** on `invPlantAvg` and `invPlantSw`. Exists only on `invBridge120` ("1 = gates live, 0 = bridge blocked"). Without it there is no way to make the inverter cease energising on a trip | Duc — **requested** |

**`Iq_ref` is contested.** `invParams.m:190` reserves it for power factor: *"Held at zero
(unity power factor) until somebody owns the Q reference — AS/NZS 4777.2 has power-factor
requirements that are nobody's task yet."* SFS needs the same port. Both cannot write it
during the islanding test. Proposed resolution: SFS owns it, power factor layered on as an
offset, since the SFS perturbation is small (±4.5° normally) and power-factor support is a
steady-state requirement.

### The form of the perturbation matters

From the rig's own output, `i_ref = I_pk·sin(ωτ + θ)`, expanded:

```
I_pk*sin(w*tau + theta) = I_pk*cos(theta)*sin(w*tau) + I_pk*sin(theta)*cos(w*tau)
                          \________ Id ________/       \________ Iq ________/
```

So the dq equivalent **holds the current magnitude constant and rotates the vector**:

```
Id_ref = I_pk*cos(theta)
Iq_ref = I_pk*sin(theta)
```

The commonly quoted `Iq_ref = Id_ref*tan(theta)` with `Id_ref` fixed is **not** equivalent —
it grows the magnitude by 1/cos θ:

| cf | θ | rotation (validated) | `Id·tan θ` |
|---|---|---|---|
| 0.05 (normal) | 4.5° | 1.000 | 1.003 |
| 0.30 (runaway) | 27° | 1.000 | **1.12** |
| 0.50 (`cf_max`) | 45° | 1.000 | **1.41** |

Indistinguishable in normal operation; a 12–41% overcurrent during a runaway, which is the
only time SFS matters. **Specify the rotation form.**

**Workflow note.** Duc's models are generated from `.m` build scripts (`buildInvLib.m`,
`buildInvPlantAvg.m`, `buildInvPlantSw.m`), so integration means adding lines to a text file
that git merges normally — not editing a binary `.slx`.

---

## 9. Sources

**Primary (read directly, quoted above):**

- **IEC 62116:2014**, *Utility-interconnected photovoltaic inverters — Test procedure of
  islanding prevention measures*. Public preview: cl. 3.7 (quality factor), 3.9 (stopping
  signal), 3.10 (unintentional island), **cl. 4 (testing circuit — the three-phase
  sentence)**, cl. 5.4 (AC loads), **cl. 6.1 (test procedure — the balanced-load
  sentence)**. https://cdn.standards.iteh.ai/samples/20105/ce9a937ec61748498c4a54d61959648f/IEC-62116-2014.pdf
  *Preview is truncated — the numeric Qf value is not in it.*

- **Jemena**, *Inverter Energy System Embedded Generators Protection Requirements —
  AS/NZS 4777.2:2020*. Protection settings table for installations >30 kVA up to 200 kVA
  (3-phase): 47 Hz, 52 Hz, 2 s disconnection, 60 s reconnection delay, central protection
  relay requirements. https://www.jemena.com.au/siteassets/asset-folder/documents/electricity/embedded-generation/eg-inverter-requirements-settings-asnzs-4777-2_2020v2.pdf

**To obtain (needed to close §7):**

- **AS/NZS 4777.2:2020**, *Grid connection of energy systems via inverters, Part 2: Inverter
  requirements* — §4.3 (anti-islanding), Table 4.1/4.2 (protection set points), reconnection.
- **AS/NZS IEC 62116:2020** — full text, for the Qf value.
  https://www.standards.govt.nz/shop/asnzs-iec-621162020
- **IEEE 1547.1** — to check the gain condition derivation.

**Supporting:**

- **Action Power**, *Anti-islanding test per IEEE 1547.1-2020 & UL 1741 SB: RLC load vs grid
  simulator* — states three-phase test loads are implemented as independent per-phase RLC
  circuits. https://www.actionpowertest.com/application-notes/anti-islanding-rlc-grid

- **Ropp, Begovic & Rohatgi**, "Analysis and performance assessment of the active frequency
  drift method of islanding prevention", *IEEE Trans. Energy Conversion*, 14(3), 810–816,
  1999 — the AFD/SFS chopping-fraction formulation.
  *Citation located via search; page numbers not verified against the published article.*

- **Zeineldin & Kennedy**, "Sandia frequency-shift parameter selection to eliminate
  nondetection zones", *IEEE Trans. Power Delivery* — directly relevant to #14.
  *Not yet obtained; verify all citation details before use.*

> **Citation discipline.** The DOI `10.29081/jesr.v30i4.001`, used in the Week 5 journal
> entry, returns HTTP 404 and is not registered with Crossref even though the publisher
> prints it. Use `https://jesr.ub.ro/journal/article/view/472` instead, and check every DOI
> resolves before it goes in the report.

---

## 10. Corrections made during development

Kept because they are evidence of verification rather than assumption, and several are
worth a sentence in the report's method section.

| what went wrong | why it mattered | how it was found |
|---|---|---|
| **Spurious 45.9% THD** | An artefact of running an FFT on non-uniformly spaced solver output — the decimated Simscape log aliased a 50 Hz waveform. True value 0.48%. A defect was reported that did not exist | Resampling onto a uniform grid before the FFT. `protection_figures` now does this by construction |
| **Silent parameter failure** | A relay `Operator` was set to `>=` and the tool reported success, but the block retained `<=`. The model compiled and ran without error, testing `f ≤ 52` — true at 50 Hz — so the latch set at t = 0 and held for the whole run | Caught by inspecting the trip signal, not by any error. Fixed with `set_param(blk,'Operator',char([62 61]))`; the `>` character does not survive the tooling |
| **306 A DC offset** | A lossless inductor energised at t = 0 retains its startup DC component forever. Pre-island RMS read 47.6 A instead of 7.8 A | Fixed with an initial current (#12), deliberately **not** winding resistance, which would have changed Qf |
| **Breaker never interrupted** | Zero-crossing detection waited for current within 1e-8 A, which never occurred | Switched to `zeroCrossingDisable` |
| **Three algebraic loops** | Vpcc → control → circuit forms an unsolvable loop in three different places | Resolved by the one-sample control delay (#18) and by placing `TripGate` *before* that delay, not after |
| **Dark-theme figure export** | The MATLAB desktop theme leaked into exported figures — black canvas, grey text, illegible on a white page | All figure scripts now set colours explicitly, build invisible with `InvertHardcopy` off, and export on white. **Never call `theme()` non-interactively** — it blocked the session for 1800 s twice |
| **ΔP swept unnecessarily** | The original sweep design had 121 points across ΔP × ΔQ | Challenged on the grounds that SFS acts through phase, not real power. Confirmed analytically (#17) and the sweep was redesigned as ΔQ × Qf — 77 points, none redundant |
