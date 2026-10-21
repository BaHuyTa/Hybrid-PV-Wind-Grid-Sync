# Live demo app (roadshow, 21 Oct 2026)

`LiveDemo` makes the integration results feel live at the table. The full switching model
cannot run in real time: at a 0.5 µs step it takes minutes per simulated second. So every
case was simulated beforehand, and the app switches to the matching saved run instantly and
plays it back. Each run is a full switching-model simulation of `intSystem_aqibPLL`.

```matlab
cd models/integration/demo
LiveDemo                       % opens maximised; F11 for full screen
```

It needs base MATLAB only, not Simulink or Simscape. The runs are in `demoPack.mat` (in git, a
few MB), so a fresh clone works straight away.

## What it does

- **Idle:** the real day loops, about a minute per loop: Gullen Range NSW, 6 Oct 2026,
  06:00 to 14:00, AEMO 5-minute data (see `../profiles/README.md`). The load slider swaps
  between the three day runs at the same clock time.
- **Grid fault**, **Load shed**, **Grid lost**: each plays its own run in slow motion around
  the event (25× slower at the key moment, labelled on screen). Then it shows the measured
  PASS/FAIL result and returns to the day by itself.
- **Panels:** power flow, DC bus against ±5 % (and 800 V in a fault), phase a of the PCC voltage
  and our current (in phase means synchronised), and the PLL frequency against the relay's
  47–52 Hz band. The relay status and the result are computed from each run's logs; nothing
  is typed in.

| Key | |
|---|---|
| `1` `2` `3` | site load 50 / 150 / 250 kW |
| `F` / `S` / `I` | grid fault / load shed / grid lost |
| `A` | anti-islanding (SFS) on or off, for grid lost |
| `B`, `Esc` | back to the day |
| `Space` | pause |
| `→` | skip ahead |
| `F11` | full screen |

## The runs

All events use the operating point of `grid_dip`: 1000 W/m², 8 m/s, SCR 10 (X/R 15). The
site load is then the only thing that changes between clips.

| Button | Load | Run |
|---|---|---|
| (idle) | 50 / 150 / 250 kW | `day_load_min`, `day_load_mid`, `day_load_max` |
| Grid fault | 50 / 150 / 250 kW | `grid_dip_50`, `grid_dip_150`, `grid_dip` |
| Load shed | 50 / 150 / 250 kW | `shed_50`, `shed_150`, `shed_250` |
| Grid lost, SFS on | matched 117 kW test load | `island_sfs` |
| Grid lost, SFS off | matched 117 kW test load | `island_nosfs` |

Grid lost always uses the matched test load, the AS/NZS 4777.2 worst case, so the load slider
is greyed out for it. `grid_dip_*`, `shed_*` and `island_nosfs` are the `"demo"` scenarios in
`intScenarios.m`. They are not in the default set, so `runIntegration([])` still runs the
nine scenarios in `RESULTS.md`.

To rebuild the pack, for example after a model change (about 1.5 h on 3–5 workers):

```matlab
cd models/integration;  intPaths();
runIntegration(["day_load_min","day_load_mid","day_load_max","grid_dip","island_sfs","demo"], ...
               Model="intSystem_aqibPLL", Parallel=true);
addpath demo;  exportDemoPack();          % results/intSystem_aqibPLL/*.mat -> demo/demoPack.mat
```

## Backup

`recordDemo()` writes `LiveDemo_backup.mp4`: one loop of the day at 150, 250 and 50 kW, then
each event. It's for a laptop without MATLAB. The video is not in git; it is shared separately.
