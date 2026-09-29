function si = pvBusInput(si, P, tEnd)
%PVBUSINPUT Drive the v_dc root inport that holds the PV stage's output bus.
%
%   si = pvBusInput(si, P, tEnd)
%
%   Belal's model (since 19 Sep) takes its DC-link voltage from a root inport
%   feeding a Controlled Voltage Source. Left undriven, that inport reads 0 V
%   and the boost runs into a short. Fed here exactly as his run_pv_plots.m
%   does it, so the harness and his own script test the same thing.

ds = Simulink.SimulationData.Dataset;
ds = ds.addElement(timeseries([P.bus.Vdc; P.bus.Vdc], [0; tEnd]), "v_dc");
% Through a variable, not setExternalInput: the model is saved with its own
% ExternalInput string, and SimulationInput refuses to hold both.
si = si.setVariable("vdcInput", ds);
si = si.setModelParameter(LoadExternalInput = "on", ExternalInput = "vdcInput");
end
