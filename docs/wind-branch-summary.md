# Wind branch — one-page status for product-owner meeting 3

**Ba Huy Ta · 6 September 2026 · Team 1, Smart Grid Technologies**
Repository: github.com/BaHuyTa/Hybrid-PV-Wind-Grid-Sync, branch `wind/ac-coupled-30kw`
(branch name predates the 5 Sep decision; the content is the DC-coupled 60 kW design)

## What exists

The wind subsystem is built and tested standalone at **60 kW**, feeding the shared 700 V DC bus of
the 150 kVA plant that the team's decision record of 5 September sets out
([decisions.md](decisions.md)).

| | |
|---|---|
| Plant | PMSG → three-phase diode bridge → boost converter with MPPT → shared DC bus → 150 kVA inverter |
| Rating | 60 kW electrical at 12 m/s; 6.46 m rotor radius (12.9 m diameter), 144 rpm, 20 pole pairs; rectified 400 V; DC bus 700 V |
| Two fidelities | averaged (tuning, sweeps; ~15 s per 150 s run) and switched (Simscape Electrical, 1 µs; THD and final validation). Both read one parameter file, so they cannot disagree about a number |
| MPPT | optimal torque control by default; Perturb & Observe kept selectable |
| Interface to integration | inputs: wind speed, DC-bus voltage, enable. Output: current into the DC bus plus telemetry. The bus capacitor belongs to integration (44 mF in the test harness) |

## What has been measured (re-run at 60 kW, 6 September)

| Test | Result |
|---|---|
| Sizing closes; boost duty stays under 0.85 from cut-in to rated | 0.818 worst case, under load |
| Six operating scenarios, ten pass/fail checks (steady, step, ramp, IEC gust, cut-in/cut-out, turbulent) | 10/10 |
| Tracking efficiency, torque control | 94–100% on every scenario |
| Tracking efficiency, P&O | 90–99% except a sustained ramp, 74.1% — the reason for the default change |
| Averaged vs switched model at the rated point | every quantity within 1% (−0.82%, +0.54%, +0.04%, −0.22%) |
| Rotor response to an 8 → 12 m/s gust | 4.78 s to settle: 24× slower than the 200 ms DC-link spec, so the wind branch cannot destabilise the grid-side loops |
| Rescale 3 kW → 30 kW → 60 kW | done per unit; every result above re-verified at 60 kW without retuning, and without touching a Simulink file |
| Harmonics (switched model, FFT) | stator current THD 15.6%, the diode-bridge limitation quantified; what reaches the DC bus is 1.3% bridge ripple and a 10 kHz pulse train worth 0.045 V on the 44 mF bus |

## What changed since 3 September, and why

- **Scale.** You asked where the numbers come from. The team's answer (5 Sep) is a 250 kW
  light-industrial site: 120 kWp PV + 60 kW wind gives a 26% renewable fraction, and the 150 kVA
  inverter stays under the 200 kVA ceiling of AS/NZS 4777.2 so every success criterion still
  applies. The wind rating follows from that, not from a turbine catalogue.
- **DC-coupled, one inverter — your AC-coupling suggestion was considered and not adopted.**
  The reasons are in decisions.md: at 150 kVA one inverter is cheaper than two, and behind the
  meter an inverter outage costs a few days of generation, not site operation. The wind branch
  was rebuilt AC-coupled at 30 kW on 4 Sep and then rescaled back; because its interface is a
  current source into a regulated DC node either way, nothing in the models had to change.
- **One 60 kW turbine, not two 30 kW.** Checked 6 Sep: 60 kW direct-drive PM machines are a
  real product class (Aeolos-H 60 kW, 22.3 m rotor at 9 m/s; Danish Wind Turbines 60 kW, 16.3 m;
  IMPEC 60 kW). Two units would add a second rotor, rectifier and MPPT for no graded benefit.
- **Loads.** A 250 kW site load and the RLC islanding test load sit at the PCC. No DC load —
  decisions.md records why.
- **Sharing.** With a 250 kW load behind the meter the plant never curtails, so the power-limit
  input drafted on 4 Sep is dropped, not built.

## What I need from you

1. Sizing: 12 m/s rated gives a 12.9 m rotor, smaller and faster than the real 60 kW machines
   above (16–22 m at ~9 m/s). Rating at 9–10 m/s puts us in that range. Your preference?
2. Is a passive rectifier plus boost acceptable as the wind's AC/DC stage, given nothing graded
   measures generator-side power quality? The stator current THD is 15.6%; none of it reaches the PCC.
3. The wind MPPT default is optimal torque control, not the P&O shared with PV. Acceptable, given
   the ramp result?
