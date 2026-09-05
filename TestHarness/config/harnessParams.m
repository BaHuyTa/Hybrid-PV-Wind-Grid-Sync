function P = harnessParams(variant)
%HARNESSPARAMS Single source of truth for the DC-link loop model and its tests.
%
%   P = harnessParams()           returns the nominal (correctly tuned) parameters.
%   P = harnessParams("nominal")  same as above.
%   P = harnessParams("sluggish") returns a deliberately under-tuned controller
%                                 that violates both the overshoot and the
%                                 settling spec. Used to prove the harness
%                                 actually catches a bad design rather than
%                                 rubber-stamping whatever it is given.
%
%   Every number the model needs and every limit the tests check lives in this
%   one file. Nothing is typed into a block dialog by hand. If a spec limit
%   changes, it changes here and both the model and the tests follow.
%
%   Fields:
%     P.plant   physical parameters of the DC bus
%     P.ctrl    controller gains and limits
%     P.sim     solver settings
%     P.spec    the pass/fail contract the tests assert against

arguments
    variant (1,1) string = "nominal"
end

%% Plant -- the physical DC bus
% RESCALED 5 Sep 2026 for the 150 kVA plant (see docs/decisions.md). The bus
% carries 150 kVA / 700 V = 214 A rated, so C, Imax and every source current in
% inputs/createTestInputs.m were all multiplied by exactly 20. Because Kp = C*wc,
% the gains follow C automatically and the crossover stays at 200 rad/s -- the
% closed-loop response, and therefore every percentage and settling-time limit in
% P.spec, is identical to the 8 kW version. Only the regression baselines had to
% be regenerated, because those store absolute volts and amps.
% Capacitor balance:  C * dVdc/dt = i_src - i_out
%   i_src  current injected by the PV and wind sources        (disturbance input)
%   i_out  current drawn by the grid-side inverter            (control variable)
P.plant.C      = 44e-3;     % DC-link capacitance                          [F]
P.plant.tau_i  = 1e-3;      % inner current-loop time constant             [s]
P.plant.Vdc0   = 700;       % initial DC bus voltage                       [V]

%% Controller -- outer DC-link voltage loop
% Error convention is  e = Vdc - Vdc_ref  (measured MINUS reference).
% See docs/DESIGN_NOTES.md "Sign convention" for why this is not a typo.
P.ctrl.Vdc_ref = 700;       % DC bus voltage setpoint                      [V]
P.ctrl.Imax    = 400;       % inverter current limit, symmetric            [A]

% Tuning rule for both variants:
%   Kp = C * wc        places the loop crossover at wc
%   Ki = Kp * wc/10    places the PI zero a decade below crossover
% The only thing that changes between variants is wc.
switch variant
    case "nominal"
        % wc = 200 rad/s (~32 Hz), phase margin ~73 deg.
        % Measured against a 200 A source-current step: 2.85 % peak deviation
        % (spec 5 %) and 62 ms settling (spec 100 ms). Both have real margin.
        %
        % An earlier attempt at wc = 100 was rejected: it overshot 5.54 %, just
        % past the 5 % limit. wc = 150 met the spec but settled at 100.5 ms,
        % sitting exactly on the boundary. A design that only just passes is a
        % design that fails after the next change, so the crossover was pushed
        % to 200. See docs/DESIGN_NOTES.md "How this number was chosen".
        wc = 200;
    case "sluggish"
        % Deliberately under-tuned: the loop is too slow to absorb a source
        % step, so the bus voltage wanders 13.7 % away and takes 450 ms to come
        % back. Fails overshoot AND settling. This is the regression the
        % harness must catch.
        wc = 40;
    otherwise
        error("harnessParams:badVariant", ...
              "variant must be ""nominal"" or ""sluggish"", got ""%s"".", variant);
end

P.ctrl.wc = wc;
P.ctrl.Kp = P.plant.C * wc;
P.ctrl.Ki = P.ctrl.Kp * wc / 10;
P.ctrl.variant = variant;

%% Simulation
% Fixed-step on purpose. A variable-step solver picks different time points on
% every run, so two runs of the same model cannot be compared sample-by-sample.
% Regression diffing needs an identical time vector every time.
P.sim.dt       = 1e-4;      % fixed step, 10 kHz                           [s]
P.sim.solver   = "ode4";    % Runge-Kutta, fixed step
P.sim.stopTime = 0.5;       % default stop time                            [s]

%% Specification -- the pass/fail contract
% These are the numbers the tests assert against. They are requirements, not
% observations: they were written down before the model was tuned.
P.spec.VdcTolPct      = 1;      % settle band, % of Vdc_ref                [%]
P.spec.settleTime     = 0.100;  % must be inside the band by this time     [s]
P.spec.overshootPct   = 5;      % max transient deviation, % of Vdc_ref    [%]
P.spec.ImaxTolPct     = 1;      % allowed numerical slop on the limit      [%]
P.spec.startupTime    = 0.200;  % must reach the band from cold start      [s]

% Derived absolute limits, so the tests never recompute them inconsistently.
P.spec.VdcTolAbs      = P.spec.VdcTolPct    /100 * P.ctrl.Vdc_ref;   % [V]
P.spec.overshootAbs   = P.spec.overshootPct /100 * P.ctrl.Vdc_ref;   % [V]
P.spec.ImaxAbs        = (1 + P.spec.ImaxTolPct/100) * P.ctrl.Imax;   % [A]

end
