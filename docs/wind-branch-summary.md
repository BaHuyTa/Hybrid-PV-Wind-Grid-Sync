# Wind branch — one-page status for product-owner meeting 3

**Ba Huy Ta · 5 September 2026 · Team 1, Smart Grid Technologies**
Repository: github.com/BaHuyTa/Hybrid-PV-Wind-Grid-Sync, branch `wind/ac-coupled-30kw`

## What exists

The wind subsystem is built and tested standalone, at the new 30 kW rating and on its own DC link,
as you asked on 3 September.

| | |
|---|---|
| Plant | PMSG → three-phase diode bridge → boost converter with MPPT → DC link 2 → inverter 2 (the wind's AC/DC/AC converter, with the boost inside the AC/DC half) |
| Rating | 30 kW electrical at 12 m/s; 4.57 m rotor radius, 203 rpm, 16 pole pairs; rectified 400 V; DC link 2 at 700 V |
| Two fidelities | averaged (tuning, sweeps; ~15 s per 150 s run) and switched (Simscape Electrical, 1 µs; THD and final validation). Both read one parameter file, so they cannot disagree about a number |
| MPPT | optimal torque control by default; Perturb & Observe kept selectable |
| Interface to integration | inputs: wind speed, DC-link-2 voltage, enable. Output: current into DC link 2 plus telemetry. The link capacitor belongs to integration |

## What has been measured

| Test | Result |
|---|---|
| Sizing closes; boost duty stays under 0.85 from cut-in to rated | 0.818 worst case, under load |
| Six operating scenarios, ten pass/fail checks (steady, step, ramp, IEC gust, cut-in/cut-out, turbulent) | 10/10 |
| Tracking efficiency, torque control | 98–100% on every scenario |
| Tracking efficiency, P&O | 96–99% except a sustained ramp, 74% — the reason for the default change |
| Averaged vs switched model at the rated point | every quantity within 1% |
| Rotor response to an 8 → 12 m/s gust | 4.78 s to settle: 24× slower than the 200 ms DC-link spec, so the wind branch cannot destabilise the grid-side loops |
| Rescale 3 kW → 30 kW | done per unit; every result above re-verified at 30 kW without retuning |
| Harmonics (switched model, FFT) | stator current THD 15.5%, the diode-bridge limitation quantified; what reaches DC link 2 is 1.2% bridge ripple and a 10 kHz pulse train that sets C_dc2 |

## What changed because of your feedback

- AC-coupled: the wind branch now feeds its own DC link and inverter, not a bus shared with PV. Your three reasons (inverter cost and capacity, single point of failure, convention) are recorded in the README.
- Loads: a DC load on the PV bus and an AC load on the AC bus are in the architecture diagram; integration and control own the models.
- Demand: a draft design basis (25 kW AC + 3 kW DC, a rural site on a weak feeder) is in the README for the team to ratify or replace. Every number in the wind sizing table now cites where it came from.
- Sharing: grid-connected, both sources run at maximum power and the grid balances. When export is limited, the sources back off in proportion to capacity; that needs a power-limit input on the wind branch, which is specified but not yet built.

## What I need from you

1. Is the draft demand basis the right shape, or do you have a load profile in mind?
2. Sizing: 12 m/s rated gives a 9.1 m rotor, smaller and faster than commercial 30 kW machines (13.5–15.6 m at 9–11 m/s). Rating at 10 m/s puts us in that range. Your preference?
3. Is a passive rectifier plus boost acceptable as the wind's AC/DC stage, given nothing graded measures generator-side power quality?
