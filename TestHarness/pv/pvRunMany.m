function outs = pvRunMany(si)
%PVRUNMANY Run an array of SimulationInputs -- in parallel if a pool is open.
%
%   outs = pvRunMany(si)
%
%   Uses the pool if one exists and never opens one: how many workers this
%   machine can afford is the caller's call (each Simscape worker is ~1.5 GB).
%   A run that errors raises here, naming the run, rather than coming back as an
%   empty logsout that some later metric turns into a plausible-looking number.

if isempty(si)
    outs = Simulink.SimulationOutput.empty;
    return
end

if ~isempty(gcp("nocreate"))
    outs = parsim(si, ShowProgress = "off", ShowSimulationManager = "off", ...
                  TransferBaseWorkspaceVariables = "off", StopOnError = "on");
else
    outs = sim(si, ShowProgress = "off", StopOnError = "on");
end

for k = 1:numel(outs)
    msg = outs(k).ErrorMessage;
    if ~isempty(msg)
        error("pvRunMany:simFailed", "Run %d of %d (%s) failed:\n%s", ...
              k, numel(outs), si(k).ModelName, msg);
    end
end
end
