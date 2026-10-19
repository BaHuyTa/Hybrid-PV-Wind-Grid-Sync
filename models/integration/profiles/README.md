# Real-day weather profiles

`gullen_2026-10-06.csv`: 5-minute measured output of the Gullen Range site near Goulburn, NSW,
06:00 to 14:00 on 6 Oct 2026 (NEM market time, AEST, interval ending), with the NSW spot price.

| Column | Unit | Unit ID | What it is |
|---|---|---|---|
| `GULLRSF1_MW` | MW | GULLRSF1 | Gullen Solar Farm, 10 MW |
| `GULLRWF1_MW`, `GULLRWF2_MW` | MW | GULLRWF1, GULLRWF2 | Gullen Range Wind Farm, two units |
| `NSW_RRP` | $/MWh | NSW1 | regional spot price, used to rule out self-curtailment |

**Source:** AEMO, NEMWEB `Reports/Archive/Dispatch_SCADA` (unit SCADA values, public), and
AEMO aggregated price and demand data for NSW1. Data © AEMO, used under AEMO's copyright
permissions with attribution.

**How the day was chosen (19 Oct 2026).** Every day from 1 Sep to 17 Oct 2026 was scored over
07:00 to 18:00:
- cloud variability in the solar output
- the range of the wind output
- intervals where PV + wind (scaled) exceed 150 kVA
- negative NSW prices while the sun was up

A negative price makes a solar farm curtail itself, which would look like cloud. Days where
both farms drop to zero together were rejected: a shared network or export constraint, not
weather (10 and 12 Oct). 6 Oct, 06:00 to 14:00, has the sunrise ramp, wind rising four-fold,
heavy cloud after noon, and no negative price.

**Scaling to our plant** (`gullenProfile.m`):
- irradiance: G = 1000 W/m² × solar output / 9.90 MW
- wind speed: v = 12 m/s × (wind output / 265.8 MW)^(1/3)

The wind formula inverts our turbine's cubic curve below rated, so the scaled wind power follows
the farm's. 9.90 and 265.8 MW are the 99.9th percentiles over the 47 days.

Limits worth stating:
- A solar farm clips at its inverter rating, so its brightest hours read as a flat 1000 W/m².
- A wind farm's aggregate curve is smoother than one turbine's.
- The day is compressed 6000× (5 min to 50 ms). The turbine inertia is scaled 1/60 for these
  runs so the rotor settles within one sample; the electrical dynamics are not compressed.
