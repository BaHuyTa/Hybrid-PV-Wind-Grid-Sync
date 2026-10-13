# Design decisions

One entry per decision that shapes the architecture. Each records what was decided,
why, and what it rules out — so nobody re-opens a settled question without new
information, and nobody builds on a choice without knowing its cost.

---

## 2026-09-05 — Scale: light-industrial site, 150 kVA

**Decided.** The plant is sized for a light-industrial site behind the meter: a factory
with ~250 kW peak demand on a 400 V connection.

| | Before | Now |
|---|---|---|
| PV | 5 kW | 120 kWp DC |
| Wind | 3 kW | 60 kW |
| Inverter | 8 kW | 150 kVA |
| DC bus | 700 V | 700 V (unchanged) |
| Grid | 400 V, 50 Hz | 400 V, 50 Hz (unchanged) |
| Site load | none | 250 kW |

**Why.** The supervisor's review on 3 Sep asked why the ratings were 5 kW and 3 kW, and
the honest answer was that they were arbitrary. Design starts from demand. A 250 kW site
gives every rating a reason: PV and wind together deliver ~285 MWh/yr against ~1.1 GWh/yr
of site consumption, a 26% renewable fraction, which is a realistic behind-the-meter
offset rather than a number picked to look good.

**Why 150 kVA specifically.** AS/NZS 4777.2 applies to inverters up to 200 kVA. Staying
under that ceiling is what keeps the standard — and therefore every success criterion in
the README — applicable. Going above it would move the project under the NER generator
performance standards, which demand fault ride-through and reactive capability curves
that are not in scope.

**Why not larger.** A megawatt-scale plant was considered and rejected. At MW scale the
turbines become Type-4 machines on an AC collector network, so the architecture is forced
to AC-coupled; AS/NZS 4777.2 stops applying; and Sandia Frequency Shift stops being the
right anti-islanding technique, since plants that size use transfer trip. It would be a
different project, proposed at week 6 with weeks 8–11 already a serial dependency chain.

**Cost of the change.** Low, by construction. Bus voltage and grid voltage are unchanged,
so only currents scale. Every derived wind quantity falls out of one line in
`models/wind/windParams.m`. `TestHarness/pv/pvParams.m` needed **no change at all** — every
limit in it is a percentage, a time, or the 700 V bus voltage, none of which scale.

---

## 2026-09-05 — Architecture: DC-coupled retained, one inverter

**Decided.** Keep the shared DC bus and the single grid-tie inverter.

**Why, against the supervisor's suggestion.** The review raised two arguments for moving
wind to an AC bus with its own inverter. Both are scale-dependent, and neither survives at
150 kVA:

1. **Inverter capacity and cost.** True at MW scale, where central inverters top out
   around 4–6 MW and 42 MW must be split. At 150 kVA we are in the most mass-produced
   size band there is; one unit is cheaper than two because inverter cost per kW falls
   with size in this range, and the enclosure, grid relay, comms and certification are
   paid for once instead of twice.
2. **Single point of failure.** Technically true at any scale, but this plant is
   grid-connected and behind the meter. If the inverter fails the site keeps running on
   grid supply — the loss is generation revenue for a few days, not site operation.
   Nobody specifies inverter redundancy at 150 kVA because the outage costs less than the
   second inverter.

**Supporting.** Sizing one inverter for the *combined* peak rather than the sum of the
two source peaks saves capacity outright: PV and wind do not peak together, so the
diversity between them is capacity we do not have to install.

**What it rules out.** N+1 redundancy is not in the design. Note that DC-coupling and
redundancy are *not* mutually exclusive — parallel inverters on the same shared DC bus
would give N+1 without becoming AC-coupled — but parallel operation brings load sharing
and circulating current, which is a research topic of its own and is out of scope.

---

## 2026-09-05 — Loads: AC loads in, DC load out

**Decided.** Add two loads at the PCC. Add none to the DC bus.

| Load | What | Why |
|---|---|---|
| Site load | 250 kW constant PQ at the PCC | Justifies the PV and wind ratings; gives the energy narrative |
| RLC test load | Parallel R-L-C tuned to 50 Hz, Qf ≈ 1, matched to inverter output | The islanding test circuit specified by AS/NZS 4777.2 / IEEE 1547.1. A test fixture, not a site asset |

**Why the load is not optional.** The non-detection zone is *defined* by the local load.
The NDZ exists precisely when local generation ≈ local load and that load resonates near
50 Hz: open the breaker and voltage and frequency barely move, so the inverter cannot
tell it has islanded. With no load, the breaker opens, voltage collapses immediately,
detection is trivial, and there is no NDZ to analyse. Without a load the protection
workstream has nothing to measure.

**Why no DC load,** despite the supervisor asking for one. It contributes nothing to grid
synchronisation, and the disturbance it would create on the DC bus can already be excited
by an irradiance step. A DC load belongs in a DC-microgrid study, which this is not. This
is a decision, not an omission — if it is wanted anyway, it is cheap and can be added as
a disturbance scenario only.

---

## 2026-09-23 — PV MPPT judged by IEC 62891 / EN 50530, not by the harness's own scenarios

**Decided.** The PV stage's MPPT is verified with the standard efficiency procedure
(`TestHarness/pv/runPVIEC.m`). The harness's six hand-written scenarios (`runPVAll`)
stay, as regression.

**Why.** The six scenarios all run at 25 °C, where the panel's maximum-power voltage
barely moves with irradiance — so a voltage-reference P&O starts every one of them
already at the peak, and scores 100 % with 0 s reacquisition. That is a test that
cannot fail, not a pass. The standard fixes both gaps: it spans three MPP voltages
and seven power levels (static), and it scores **energy** over defined irradiance
ramps (dynamic), which is where P&O loses.

**Which standard.** IEC 62891:2020 (EN 50530:2010+A1:2013 is its European
predecessor). No Australian standard covers MPPT efficiency — AS/NZS 4777.2 governs
the grid side only — so the report should cite IEC 62891 for the PV stage and
AS/NZS 4777.2 for the inverter. Test values were taken from a TÜV Rheinland EN 50530
test report and must be checked against the IEC 62891 text before citing.

**Adaptations, stated so they are not mistaken for compliance:** MPP voltage is moved
with cell temperature (15 / 25 / 75 °C) rather than a PV simulator; the 300 s
stabilisation wait is replaced by the derived time for P&O to reach the peak; the
default profile runs the three fastest ramp slopes per sequence, one cycle each,
because the full procedure is days of switched-model simulation. Pass marks (98 %
static EUR-weighted, 98 % dynamic mean) are the harness's — the standard sets none.

**First result (23 Sep, Belal's 19 Sep model):** dynamic passes (mean 99.2 %). Static
fails: near 0 % at 75 °C below full power, and at 5 % power at 25 °C. Cause: P&O
starts its voltage reference at a fixed 360 V, which is above the panel's open-circuit
voltage on a hot or dim array; the panel is held at open circuit and the tracker never
finds the slope down. Fix is Belal's (see `TestHarness/pv/results/iec/`).

---

## 2026-10-02 — Integration: shared 700 V bus with stand-in DC-link loop and PLL

**Decided.** `models/integration/` joins PV (pv-v2), wind and the inverter on one 700 V
bus, modelled as `C·dv/dt = i_pv + i_wind − i_inv` with C = 44 mF. Each component takes
`v_dc` in and gives its DC current out. Two stand-ins fill the gaps until the real blocks
fit: a DC-link voltage PI that commands the inverter's `Id_ref`, and an SRF-PLL in place of
`GridAngle_ideal`. Aqib's `SRF_PLL` is already a drop-in and runs in `intSystem_aqibPLL.slx`.

**DC-link gains: P 18.714, I 18.714 × 94.79 = 1774** (A pk per V), clamp ±306.2 A with
anti-windup. Tuned by Henry in Control System Designer on the plant
`1/(1.429·0.044·s) · 1/(s/3142 + 1)` (bus + current loop, in the block's d-axis units):
crossover 310 rad/s, 10× below the 500 Hz current loop; phase margin 67°. They replace the
harness gains (12.57 / 251.5): bus deviation 2.14 → 1.21 %, recovery 60 → 12 ms, THD
unchanged.

**Why a signal-level bus and not a Simscape capacitor.** PV's negative rail is grounded
and the grid has a neutral; a physical capacitor joining them closes a DC short.

**Result (2 Oct):** nominal, cloud, gust and weak grid pass every success criterion;
`checkBuild` 44/44. Over-rating fails by design of the scenario: nothing curtails PV + wind
above 150 kVA. Numbers and figures: `models/integration/results/RESULTS.md`.

**Which blocks the system keeps (Henry, 2 Oct):** the **DC-link voltage loop is this one**
(`DCLinkLoop_standin`, Henry's gains), not Aqib's: his drives a battery current source, and
the system has no battery (see out of scope). The **PLL is Aqib's `SRF_PLL`**; the PLL
stand-in stays only until his block starts at −π/2.

**Open:** curtailment (team), weak-grid PLL frequency ripple and the `SRF_PLL` start angle
(Aqib), PV diode Ron (Belal).

---

## Deliberately out of scope

Recorded so they read as decisions rather than gaps:

- **No DC load** — see above.
- **No parallel inverters / N+1 redundancy** — see above.
- **No battery storage.** Nothing in the success criteria measures it, and it would add a
  bidirectional converter and an energy-management layer.
- **No pitch control.** Fixed β = 0, stall-regulated. See `wind-model-spec.md`.
- **No two-mass drivetrain.** Single lumped inertia. No criterion needs the torsional mode.

---

## 2026-10-05 — Anti-islanding in the integration: SFS owns `Iq_ref`; trip blocks the gates

**Decided (Henry).** In the integrated model SFS writes the current reference, in Redhwan's
rotation form (Id = |I|cos θ, Iq = |I|sin θ, θ = (π/2)·cf), between the DC-link loop and the
trip gate. Power factor stays at unity underneath it (`ip.Iq_ref` = 0), so nothing else needs
`Iq_ref` today. A trip blocks all six bridge gates (gates × enable) as well as zeroing the
references and stopping both boosts. Redhwan's relay is linked from `protectionLib`, OR'd with
the integration's stand-in trip so the trip-path test keeps working.

**Integration settings that differ from the rig:** `t_arm` = 0.3 s (our island forms at 0.5 s);
SFS acts on a one-cycle-smoothed frequency (τ = 20 ms) and starts at `t_arm`. Fed Aqib's raw PLL
estimate, SFS destabilised the SCR-3 grid; the rig's once-per-cycle estimator never showed it.

**Result (5 Oct, copy of `intSystem_aqibPLL`):** matched island tripped by the relay alone in
65.6 ms (SC5 limit 2 s); no nuisance trip in nominal or weak-grid runs.
