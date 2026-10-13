# Control — SRF-PLL and DC-link voltage loop

Owner: Aqib Mohamed Ameer

Two loops, each with a before/after pair so the effect of the controller is visible.

```matlab
addpath(genpath('models'));   % uses invLib/invParams (inverter) and windLib/windParams (wind) from their own folders
```

## `srf_pll/` — grid synchronisation

| file | what it is |
|---|---|
| `srfPllLib.slx` | **the SRF-PLL block.** In: `v_abc`. Out: `theta` (same `atan2(v_beta, v_alpha)` convention as `GridAngle_ideal`), `f_hz`, `vd`. Mask: `Ts`, `f0`, `fbw`, `zeta`, `theta0` (starting angle, default 0). Drop-in replacement for `GridAngle_ideal`. |
| `srf_pll_test.slx` | stand-alone test bench: synthetic 400 V / 50 Hz grid with frequency step, phase jump, sag and 5th/7th harmonics (`srcp` in the model workspace) |
| `invPlantSw_BEFORE_noPLL.slx` | Duc's switched inverter, `GridAngle_ideal` (red), grid with 5 % 5th + 3 % 7th |
| `invPlantSw_AFTER_SRFPLL.slx` | same model, `SRF_PLL` (green) drives CurrentLoop / Modulator_SVPWM / Telemetry; `GridAngle_ideal` kept only as a scope reference |
| `invPlantAvg_view.slx` / `invPlantAvg_pll.slx` | the same before/after on the averaged inverter |
| `compare_before_after.m` | runs both switched models (~2 min) and plots current, angle, harmonics and THD |

PLL design: Clarke → Park at the estimated angle → `vq` normalised by `|v|` (dynamics independent of voltage
level) → 300 Hz notch (5th and 7th both land at 6·f in dq) → PI, 25 Hz, ζ = 0.707 → frequency clamped
to f0 ± 10 Hz with conditional-integration anti-windup → angle. Runs at `ip.Ts_ctrl` (10 kHz) through an
input sample-and-hold; `theta` comes out of a Unit Delay, so the block has no direct feedthrough and does
not form an algebraic loop inside the inverter.

Stand-alone (`srf_pll_test`): locks from 170° in 69 ms; ±20° phase jump recovered in 26 ms (unchanged at
10 % voltage); ±0.5 Hz step tracked with zero steady-state error; with 5 %/3 % harmonics the angle ripple
against the true fundamental is 0.005° (`atan2` of the same voltage wobbles 2.3°).

In the inverter, grid-current THD at rated current (window 0.11–0.15 s):

| | `GridAngle_ideal` | SRF-PLL |
|---|---|---|
| switched, distorted grid | 5.55 % — **fails** < 5 % | **2.39 %** |
| switched, clean grid | 1.42 % (matches `models/inverter/README.md`) | 1.40 % |
| averaged, distorted grid | 6.34 % | 1.85 % |

On a clean grid the PLL costs nothing. On a distorted grid `atan2` of the PCC voltage wobbles ~10° pk-pk at
300 Hz and the current loop copies that into the current; the PLL filters it out.

Starting angle (`theta0`, added 5 Oct 2026): the angle estimate starts at `theta0`. Set it to the grid's
angle at t = 0, which is -pi/2 for the `invParams` grid, so the PLL starts locked. With the default 0 it starts
90 deg off and pulls in. That is harmless on a stiff grid, but on the SCR-3 grid with the 250 kW site load in
the integration the pull-in rode the +/-10 Hz clamp for ~0.1 s and charged the DC bus to 787 V (12.5 %).
With -pi/2 the peak was 712.5 V (1.8 %), weak_grid passes, and THD and PF are unchanged. The default is 0, so the test
benches and the numbers above are unchanged.

Open item (not the PLL): Id settles at ~297 A against a 306 A reference in both versions — present in the
original inverter model.

## `dc_link/` — DC bus voltage loop

| file | what it is |
|---|---|
| `dc_bus_power_management_v3.slx` | DC link (C, R_Load) with Belal's PV section (panel, MPPT, boost) and Huy's wind plant (from `windPlantSw`, v_wind = `wp.v_init`), plus the DC-link voltage loop |
| `dc_bus_BEFORE_noController.slx` | same, controller blocks commented out (red) |
| `dc_bus_AFTER_withController.slx` | same, controller active (green) |
| `compare_dcbus_before_after.m` | runs both (~6 min each for 1 s), caches `dcbus_compare_results.mat`, plots |

Controller: `V_DC_ref` (700 V) − delayed bus voltage → `PI_BusCtrl` (P 8.8, I 176, ±300 A) → battery current
source `CS_Batt`. The bus solver uses the Simscape partitioning local solver at 1 µs.

| after 1 s | no controller | with controller |
|---|---|---|
| bus voltage | 2606 V and still rising (3.7× 700 V) | 700.0 V, 1.4 V ripple, 3 % start-up overshoot, settled in ~0.2 s |
| wind current | collapses to ~4 A | ~28 A |
| battery | — | absorbs ~158 A (PV + wind surplus over the 8 kW load) |

Notes for integration (Hoang): the bus − rail is grounded here (`Gnd`). Per `models/inverter/README.md` the DC
bus must float once the grid-tied inverter is attached — remove `Gnd` then. The wind plant's `v_dc` input is
taken through a one-step delay (`Vdc_Wind_Delay`) to break the algebraic loop between the two Simscape
networks. The wind parameters are loaded in each model's workspace with the `li_inv`/`Cp` function handles
stripped, because Simulink cannot pass them into blocks.
