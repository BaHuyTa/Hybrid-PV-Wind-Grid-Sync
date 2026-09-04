# Traceability — success criteria → test → evidence

**Owner:** Ba Huy Ta (validation) · **Draft, 5 September 2026** · one row per graded requirement, and
one row per subsystem acceptance check. A row is *closed* only when the evidence column names a
script and a result somebody can regenerate. This is the format the final report's validation
chapter will use; every subsystem owner fills their own rows.

## A. Project success criteria (proposal §2.2, AS/NZS 4777.2:2020)

| # | Criterion | Requirement | Test (setup · stimulus · expected) | Model | Owner | Evidence | Status |
|---|---|---|---|---|---|---|---|
| SC1 | Current THD at rated output | < 5% at the PCC | Switched inverter at rated export into the grid model · steady state · FFT of the PCC current, THD < 5% | inverter 2 (switched), inverter 1 (switched) | Aqib, Duc | — | planned W9 |
| SC2 | DC-link voltage deviation | < 5%, recover within 200 ms, each link | Inverter with its DC-link loop · source power step (wind S2 8→12 m/s, S4 gust; PV irradiance step) · deviation < 5%, back inside band within 200 ms | inverter 2 + wind branch; inverter 1 + PV branch | Aqib, Duc (loop); Huy, Belal (stimulus) | wind stimulus ready: `wind_scenarios.m` S2, S4 | planned W8 |
| SC3 | Inner current loop | settling < 2 ms, overshoot < 10% | Inverter dq current loop · reference step · settling and overshoot from the step response | inverter (averaged, then switched) | Aqib, Duc | — | planned W7 |
| SC4 | PLL re-lock | < 100 ms after a 30° phase jump | SRF-PLL on the grid model · 30° phase jump · phase error settles within 100 ms | control | Aqib, Duc | — | planned W8 |
| SC5 | Islanding detect + disconnect | < 2 s | Both inverters exporting, matched local load · grid breaker opens · SFS detects and trips within 2 s; NDZ analysis for the two-inverter case | integration + protection | Redhwan | — | planned W9–W10 |
| SC6 | Stable operation | down to SCR = 3 | Full system on a grid model of decreasing short-circuit ratio · SCR sweep 10 → 3 · no sustained oscillation, all other criteria still met | integration (averaged) | Hoang; sweep run by Huy | bandwidth separation (24×) means any instability found is grid-side, not a plant artefact: `wind_model_check.m` §4, spec §4 | planned W11 |

What AC coupling changed: SC2 is now tested per link, and the combined worst case (PV step down at the
same instant as a wind gust up) becomes a PCC test under SC6, not a DC-link test.

## B. Wind subsystem acceptance (docs/wind-model-spec.md §2, §5) — all closed 4 Sep 2026, 30 kW

| # | Check | Requirement | Script | Result | Evidence |
|---|---|---|---|---|---|
| W1 | Sizing closes | duty < 0.85 from cut-in to rated; rotor settling ≫ 200 ms | `wind_model_check.m` | max duty 0.810 no-load; settling 4.78 s | script output, spec §3–4 |
| W2 | Steady tracking | ≥ 95% of achievable at rated | `wind_scenarios.m` S1 | 99.9% | harness log |
| W3 | Delivers rating | P_dc ≥ P_elec at rated | `wind_scenarios.m` S1 | 31 831 W ≥ 30 000 W | harness log |
| W4 | Step tracking | ≥ 90% through 8→12 m/s | `wind_scenarios.m` S2 | 98.4% | harness log |
| W5 | Ramp tracking | ≥ 90% through 4→12 m/s | `wind_scenarios.m` S3 | 98.5% (P&O: 74.2%, retained as mode 0) | harness log, `wind_ramp_figure.m` |
| W6 | No overspeed | ω < 1.25 ω_rated in the IEC gust | `wind_scenarios.m` S4 | 20.5 < 26.6 rad/s | harness log |
| W7 | Enable line | zero export when disabled | `wind_scenarios.m` S5 | 0 W | harness log |
| W8 | Turbulent tracking | ≥ 90% | `wind_scenarios.m` S6 | 98.1% | harness log |
| W9 | Duty headroom, under load | < 0.85 cut-in to rated | `wind_scenarios.m` | 0.818 | harness log |
| W10 | Below cut-in | saturates at 0.85, no reverse power | `wind_scenarios.m` S5 | capped at 0.850, 0 W reverse | harness log |
| W11 | Fidelity: i_L, V_rect, duty, P_dc | switched vs averaged within 3% | `wind_fidelity_check.m` | −0.91%, +0.63%, −0.05%, −0.19% | fidelity log, spec §5 |
| W12 | Switched current loop tracks its reference | within 3% | `wind_fidelity_check.m` | 97.99 A vs 98.26 A | fidelity log |
| W13 | P&O tuning | ≥ 95% at the chosen setting, robust neighbourhood | `wind_mppt_sweep.m` | 99.1%, worst neighbour 93.7% | sweep log, params table |
| W14 | Structure: library links, workspace binding, no literal design parameters | all pass | `wind_model_lint.m` | see script output | script output |
| W15 | Harmonics: stator current THD quantified; bridge ripple into DC link 2 < 10%; switching ripple at f_sw consistent with time domain | 6 checks | `wind_thd_check.m` | THD 15.5%; 6 f_e into link 0.58 A of 47 A; 14.1 A at 10 kHz vs 16.5 A predicted | script output, results/thd_spectra.png |

Regenerate everything in section B with:

```matlab
addpath(genpath('params'), genpath('scripts'), genpath('models'));
wind_model_check; wind_model_lint; wind_scenarios; wind_fidelity_check; wind_mppt_sweep; wind_thd_check;
```
