# Traceability — success criteria → test → evidence

**Owner:** Ba Huy Ta (validation) · **Draft, 6 September 2026** · one row per graded requirement, and
one row per subsystem acceptance check. A row is *closed* only when the evidence column names a
script and a result somebody can regenerate. This is the format the final report's validation
chapter will use; every subsystem owner fills their own rows.

## A. Project success criteria (proposal §2.2, AS/NZS 4777.2:2020)

| # | Criterion | Requirement | Test (setup · stimulus · expected) | Model | Owner | Evidence | Status |
|---|---|---|---|---|---|---|---|
| SC1 | Current THD at rated output | < 5% at the PCC | Switched 150 kVA inverter at rated export into the grid model · steady state · FFT of the PCC current, THD < 5% | inverter (switched) | Aqib, Duc | — | planned W9 |
| SC2 | DC-link voltage deviation | < 5%, recover within 200 ms | DC-link loop on the shared bus · source current step (wind S2 8→12 m/s, S4 gust; PV irradiance step; both together) · deviation < 5%, back inside band within 200 ms | `TestHarness` DC-link loop + wind and PV branches | Aqib, Duc (loop); Huy, Belal (stimulus) | harness: 2.85% / 62 ms on a 0→200 A step (`harnessParams.m`). Wind stimulus ready: `wind_scenarios.m` S2, S4 (~28→95 A over 5 s) | harness closed for the synthetic step; wind-driven case planned W8 |
| SC3 | Inner current loop | settling < 2 ms, overshoot < 10% | Inverter dq current loop · reference step · settling and overshoot from the step response | inverter (averaged, then switched) | Aqib, Duc | — | planned W7 |
| SC4 | PLL re-lock | < 100 ms after a 30° phase jump | SRF-PLL on the grid model · 30° phase jump · phase error settles within 100 ms | control | Aqib, Duc | — | planned W8 |
| SC5 | Islanding detect + disconnect | < 2 s | Inverter exporting into the RLC test load (Qf = 1) with the 250 kW site load · grid breaker opens · SFS detects and trips within 2 s; NDZ analysis | integration + protection | Redhwan | — | planned W9–W10 |
| SC6 | Stable operation | down to SCR = 3 | Full system on a grid model of decreasing short-circuit ratio · SCR sweep 10 → 3 · no sustained oscillation, all other criteria still met | integration (averaged) | Hoang; sweep run by Huy | bandwidth separation (24×) means any instability found is grid-side, not a plant artefact: `wind_model_check.m` §4, spec §4 | planned W11 |

## B. Wind subsystem acceptance (docs/wind-model-spec.md §2, §5) — all closed 6 Sep 2026, 60 kW

| # | Check | Requirement | Script | Result | Evidence |
|---|---|---|---|---|---|
| W1 | Sizing closes | duty < 0.85 from cut-in to rated; rotor settling ≫ 200 ms | `wind_model_check.m` | max duty 0.810 no-load; settling 4.78 s | script output, spec §3–4 |
| W2 | Steady tracking | ≥ 95% of achievable at rated | `wind_scenarios.m` S1 | 99.9% | harness log |
| W3 | Delivers rating | P_dc ≥ P_elec at rated | `wind_scenarios.m` S1 | 63 666 W ≥ 60 000 W | harness log |
| W4 | Step tracking | ≥ 90% through 8→12 m/s | `wind_scenarios.m` S2 | 98.4% | harness log |
| W5 | Ramp tracking | ≥ 90% through 4→12 m/s | `wind_scenarios.m` S3 | 98.5% (P&O: 74.1%, retained as mode 0) | harness log, `wind_ramp_figure.m` |
| W6 | No overspeed | ω < 1.25 ω_rated in the IEC gust | `wind_scenarios.m` S4 | 14.5 < 18.8 rad/s | harness log |
| W7 | Enable line | zero export when disabled | `wind_scenarios.m` S5 | 0 W | harness log |
| W8 | Turbulent tracking | ≥ 90% | `wind_scenarios.m` S6 | 98.1% | harness log |
| W9 | Duty headroom, under load | < 0.85 cut-in to rated | `wind_scenarios.m` | 0.818 | harness log |
| W10 | Below cut-in | saturates at 0.85, no reverse power | `wind_scenarios.m` S5 | capped at 0.850, 0 W reverse | harness log |
| W11 | Fidelity: i_L, V_rect, duty, P_dc | switched vs averaged within 3% | `wind_fidelity_check.m` | −0.82%, +0.54%, +0.04%, −0.22% | fidelity log, spec §5 |
| W12 | Switched current loop tracks its reference | within 3% | `wind_fidelity_check.m` | 196.0 A vs 196.5 A | fidelity log |
| W13 | P&O tuning | ≥ 95% at the chosen setting, robust neighbourhood | `wind_mppt_sweep.m` | 99.1%, worst neighbour 93.6% | sweep log, params table |
| W14 | Structure: library links, workspace binding, no literal design parameters | all pass | `wind_model_lint.m` | 9/9 | script output |
| W15 | Harmonics: stator current THD quantified; bridge ripple into the DC bus < 10%; switching ripple at f_sw consistent with time domain | 6 checks | `wind_thd_check.m` | THD 15.6%; 6 f_e into bus 1.26 A of 95 A; 28.1 A at 10 kHz vs 33.3 A predicted | script output, results/thd_spectra.png |

Regenerate everything in section B with:

```matlab
addpath(genpath('params'), genpath('scripts'), genpath('models'));
wind_model_check; wind_model_lint; wind_scenarios; wind_fidelity_check; wind_mppt_sweep; wind_thd_check;
```
