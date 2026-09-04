# Hybrid PV–Wind System with Grid Synchronization

Grid-connected hybrid PV and wind system, delivered entirely in simulation.
**SEDE Studios, Spring 2026 — Team 1, Smart Grid Technologies.**

Product Owner: Mohammad Abuhilaleh · Coordinators: Valerie Gay, Dayna Sais, Can Ding

## What it is

> **Architecture change — 4 September 2026.** After the product-owner meeting the
> system is **AC-coupled**, and the wind branch is rated **30 kW** (was 3 kW).
> Each source now has its own DC link and its own grid-tie inverter, and the two
> inverters meet on the AC bus at the point of common coupling. The shared 700 V
> DC bus is gone. See [docs/dc_vs_ac_coupled.png](docs/dc_vs_ac_coupled.png) for
> the two topologies side by side. Everything below reflects the new design; the
> roadshow deck of 2 September still shows the old one.

AC-coupled design. A 5 kW PV array feeds a boost converter under Perturb & Observe
MPPT into its own DC link and inverter. A 30 kW PMSG wind subsystem feeds a rectifier
and boost into a second DC link and a second inverter. Each inverter is a three-phase
SVPWM voltage-source inverter with an LCL filter, dq-frame PI current control and an
SRF-PLL; the two connect in parallel on the AC bus. Anti-islanding uses Sandia
Frequency Shift on each inverter, assessed by non-detection zone analysis against
AS/NZS 4777.2:2020.

Indicative ratings: 5 kW PV + 30 kW wind, each through its own 700 V DC link and
inverter → 400 V, 50 Hz grid.

```
PV array ──► boost + P&O MPPT ──► DC link 1 ──► inverter 1 (VSI + LCL) ──┐
                                                  + SRF-PLL, dq loop, SFS  ├──► AC bus ──► grid (PCC)
wind ──► PMSG ──► rectifier ──► boost + MPPT ──► DC link 2 ──► inverter 2 ──┘
                                                  + SRF-PLL, dq loop, SFS
```

What AC coupling changes for the build: two PLLs, two dq current loops, two DC-link
loops and two SFS instances instead of one of each. The inverter is designed once and
instantiated twice at different ratings (5 kW and 30 kW). The interaction between two
grid-tied inverters on one PCC — which the DC-coupled design avoided by construction —
is now part of the problem, and it is where the weak-grid (SCR = 3) work lands.

## Success criteria

| Metric | Target |
|---|---|
| Current THD at rated output | < 5% |
| DC-link voltage deviation (each DC link) | < 5%, recover within 200 ms |
| Inner current loop settling | < 2 ms, overshoot < 10% |
| PLL re-lock after 30° phase jump | < 100 ms |
| Islanding detect + disconnect | < 2 s |
| Stable operation | down to SCR = 3 |

## Layout

```
docs/         proposal, subsystem specs
params/       shared parameter files — single source of truth
models/
  wind/       turbine, PMSG, rectifier, boost      Huy
  pv/         PV array, boost, MPPT                Belal
  control/    SRF-PLL, dq current loop, DC-link    Aqib, Duc
              loop - one design, two instances
  protection/ SFS anti-islanding (x2), NDZ         Redhwan
  integration/ top-level model, DC links 1 and 2,  Hoang
              AC bus / PCC, harness
scripts/      analysis + verification scripts
tests/scenarios/  test cases and expected results
```

## Team

| Name | Area | Studio |
|---|---|---|
| Hoang Gia Khiem Khuc | Integration, test harness | Application Studio B |
| Ba Huy Ta | Wind plant, validation | Professional Studio B |
| Duc Pham | Control design | Professional Studio B |
| Belal Abu-issa | PV plant | Professional Studio B |
| S M Redhwan Ahmed | Protection, anti-islanding | Professional Studio A |
| Aqib Mohamed Ameer | Control design | Professional Studio B |

## Getting started

Requires MATLAB R2026a with Simulink, Simscape and **Simscape Electrical**.
Control System Toolbox and Simulink Control Design are used for loop tuning.

> **Correction (Sep 2026):** this previously said *Specialized Power Systems*.
> That product is **not installed** on the lab image — `powerlib` does not exist
> there. The wind switched model is built from foundation Simscape Electrical
> (`ee_lib`), which is present and sufficient. If your subsystem plan assumed SPS
> blocks, check before you build.

```matlab
addpath(genpath('params'), genpath('scripts'), genpath('models'));
wp = windParams();      % load wind subsystem parameters
wind_model_check        % sizing arithmetic only - no Simulink needed
wind_scenarios          % 6 scenarios, 10 checks, both MPPT modes
wind_fidelity_check     % averaged vs switched cross-validation
```

## Working on models

**Simulink `.slx` files are binary. Git cannot merge them.** If two people edit the
same model on different branches, resolving the conflict means one side's work is
lost. `.gitattributes` marks them binary so git fails loudly instead of corrupting
a model with a bogus text merge.

To stay out of trouble:

- **Own your file.** Work only inside your own `models/<area>/` directory. If you
  need a change in someone else's model, ask them — don't edit it.
- **Say so before editing a shared model.** `models/integration/` is Hoang's. Post
  in the chat before touching it, and push as soon as you're done.
- **Never put a constant in a block mask.** Put it in `params/` and reference it.
  Parameter files are plain `.m`, so they diff and merge normally — this is how we
  avoid most model conflicts in the first place.
- **Small, frequent commits.** A day of unpushed model work is a day at risk.

## Conventions

- Every subsystem exposes its parameters through one file in `params/`.
- Two fidelities per plant: **averaged** for controller tuning and parameter sweeps,
  **switched** for THD and final validation. Both read the same parameter file so
  they cannot drift.
- Simulation outputs (`.mat`, `.csv`, figures) are gitignored — commit the script
  that regenerates them, not the result.

## Bandwidth separation

Loops are tuned inside-out. The separation is what makes that valid:

| Loop | Owner | Speed |
|---|---|---|
| Grid-side inner current loop (per inverter) | Aqib, Duc | 2 ms settling |
| DC-link voltage loop (per inverter) | Aqib, Duc | ~200 ms recovery |
| Source-side boost + MPPT | Huy, Belal | ~1 s |
| Wind rotor (mechanical) | Huy | ~4.8 s measured — unchanged at 30 kW |

The wind branch is built and tested standalone: two fidelities, cross-validated to under 1%, with
a 6-scenario / 10-check harness. See [docs/wind-model-spec.md](docs/wind-model-spec.md) §6a.

The rotor is ~24× slower than the DC-link loop, so the control pair can tune the
cascade without modelling wind dynamics. It also means instability found at low SCR
is genuinely a grid-side effect rather than a plant artifact. The 30 kW rescale did
not move this number: inertia constant, tip-speed ratio and the Cp curve are all
unchanged, so the rotor's response in seconds is identical.

With AC coupling the wind branch no longer disturbs the PV inverter through a shared
bus. Its transients reach the PV branch only through the AC bus, as a change in the
power inverter 2 exports — which is what the SCR sweep is for.

## Open assumptions

Not yet confirmed with the team — flagged so nobody builds on them unknowingly:

- Wind rated speed **12 m/s** and cut-in **4 m/s** are assumed, not from the
  proposal. All wind sizing follows from them. At 30 kW that gives a **9.1 m rotor**
  turning at **203 rpm**. Commercial 30 kW turbines are larger and slower: Aeolos-H
  30 kW is 15.6 m rated at 9 m/s, Zenia 30 kW is 13.8 m, Kodair KW30 is 14.1 m at
  ~11 m/s, Renery RW-30 is 13.5 m rated at 10 m/s and 90 rpm. Rating ours at
  **10 m/s** instead would give a 12 m rotor at 129 rpm — inside that envelope. It is
  a one-line change in `params/windParams.m`, but it moves every wind-side number,
  so it is a team decision. See [docs/wind-model-spec.md](docs/wind-model-spec.md) §7.
- The 30 kW PMSG has **16 pole pairs** (was 10 at 3 kW) so the electrical frequency
  stays at 54 Hz at the slower rated speed. Commercial 30 kW direct-drive PM
  generators are offered at 200–500 rpm; a 200 rpm unit wound for 50 Hz has 15 pole
  pairs, so this is a conventional choice. Only the flux linkage depends on it.
- Wind uses a passive diode bridge + boost rather than an active rectifier. See
  [docs/wind-model-spec.md](docs/wind-model-spec.md) for the reasoning. The
  architecture diagram labels the wind front end just "Rectifier"; the boost is
  inside that box, and it is what does the MPPT.
- **DC link 2 is 700 V**, matching DC link 1, so the two inverters can be one design.
  Its capacitor is owned by integration, not by the wind branch — same rule as before,
  now applied per link. Needs Hoang's and the control pair's agreement.
- **The wind MPPT default is now optimal torque control, not P&O.** P&O tracks 96-99% in steady
  and turbulent wind but only 74% through a sustained ramp, because rising wind makes every
  perturbation look successful. Both are built and selectable (`wp.mppt_mode`); P&O is not
  deleted. This affects the claim that both plants share one MPPT algorithm, so it needs a team
  decision — see [docs/wind-model-spec.md](docs/wind-model-spec.md) §2.
