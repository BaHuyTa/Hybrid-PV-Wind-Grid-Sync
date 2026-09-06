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
`params/windParams.m`. `TestHarness/pv/pvParams.m` needed **no change at all** — every
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

## Deliberately out of scope

Recorded so they read as decisions rather than gaps:

- **No DC load** — see above.
- **No parallel inverters / N+1 redundancy** — see above.
- **No battery storage.** Nothing in the success criteria measures it, and it would add a
  bidirectional converter and an energy-management layer.
- **No pitch control.** Fixed β = 0, stall-regulated. See `wind-model-spec.md`.
- **No two-mass drivetrain.** Single lumped inertia. No criterion needs the torsional mode.
