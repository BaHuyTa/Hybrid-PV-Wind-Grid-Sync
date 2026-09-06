# --- front-matter:toml ---
model = "DCLinkLoop.slx"
[inputs]
Vdc_ref = "Vdc_ref"
i_src = "i_src"
[outputs]
Vdc = "Vdc"
i_out = "i_out"
# --- end front-matter ---

Feature: DC-link voltage loop holds the bus against source disturbances
  Gherkin translation of the scenario library in inputs/createTestInputs.m.
  All limits are the same numbers as config/harnessParams.m:
  setpoint 700 V, tolerance band 7 V (1%), overshoot 35 V (5%),
  settling 100 ms after the event, inverter current limit 404 A.
  Numeric literals are unavoidable here - see DESIGN_NOTES for why that
  matters, since harnessParams.m can no longer be the single source of truth.

Scenario: Source step - PV and wind come up
  Source current steps 0 to 200 A at 50 ms. The bus must stay inside the
  overshoot envelope and be back in the tolerance band 100 ms later.
  Given inputs
    * Vdc_ref = const(700)
    * i_src = step(0 -> 200 @ 50ms)
  When simulate for 500ms in Normal mode
  Then outputs
    * OvershootWithinEnvelope: Vdc == [665 .. 735]
    * SettledInBand: Vdc == [693 .. 707] when t > 150ms
    * CurrentLimitHolds: i_out == [-20.2 .. 20.2]

Scenario: Cloud transient - irradiance collapses
  Source current drops 200 to 40 A at 200 ms. Assertions start after 200 ms so
  the model's own start-up transient is not measured as a failure.
  Given inputs
    * Vdc_ref = const(700)
    * i_src = step(200 -> 40 @ 200ms)
  When simulate for 500ms in Normal mode
  Then outputs
    * OvershootWithinEnvelope: Vdc == [665 .. 735] when t > 200ms
    * SettledInBand: Vdc == [693 .. 707] when t > 300ms
    * CurrentLimitHolds: i_out == [-20.2 .. 20.2]

Scenario: Reference step - operator raises the setpoint
  Setpoint steps 700 to 750 V at 200 ms under a steady 200 A source.
  The bus must track to the new setpoint without exceeding it by 35 V.
  Given inputs
    * Vdc_ref = step(700 -> 750 @ 200ms)
    * i_src = const(200)
  When simulate for 500ms in Normal mode
  Then outputs
    * NoOvershootPastNewSetpoint: Vdc < 785
    * TrackedNewSetpoint: Vdc == [743 .. 757] when t > 300ms
    * CurrentLimitHolds: i_out == [-20.2 .. 20.2]

Scenario: Overload - source exceeds what the inverter can absorb
  Source steps to 1200 A, three times the 400 A inverter limit. Voltage
  regulation is EXPECTED to be lost here, so no voltage assertion is made.
  The only requirement that applies is that the current limit holds.
  Given inputs
    * Vdc_ref = const(700)
    * i_src = step(0 -> 1200 @ 50ms)
  When simulate for 500ms in Normal mode
  Then outputs
    * CurrentLimitHolds: i_out == [-20.2 .. 20.2]
