function p = intPaths()
%INTPATHS  Where things are, in whichever layout this folder is sitting in.
%
%   p = intPaths()      also puts the component folders on the path
%
% Two layouts, same scripts:
%   REPO     <repo>/models/integration   -> components at <repo>/models/{pv,wind,inverter}
%   SANDBOX  Integration_Sandbox/integration -> components at Integration_Sandbox/components/models
% Results always go to a results/ folder NEXT TO this file's folder in the
% sandbox, or INSIDE it in the repo (add models/integration/results/ to .gitignore).

p.here = fileparts(mfilename('fullpath'));
up     = fileparts(p.here);
if isfolder(fullfile(up, 'inverter'))
    p.layout  = "repo";
    p.models  = up;
    p.results = fullfile(p.here, 'results');
else
    p.layout  = "sandbox";
    p.models  = fullfile(up, 'components', 'models');
    p.results = fullfile(up, 'results');
end
% Belal moved PV to models/pv-v2 on main (c86f01c, 27 Sep); use it when present.
if isfolder(fullfile(p.models, 'pv-v2')), p.pv = fullfile(p.models, 'pv-v2');
else,                                     p.pv = fullfile(p.models, 'pv');
end
p.wind = fullfile(p.models, 'wind');
p.inverter = fullfile(p.models, 'inverter');
addpath(p.here, p.pv, p.wind, p.inverter);
% Aqib's SRF-PLL library (models/control, on main from 27 Sep)
p.control = fullfile(p.models, 'control');
if isfolder(fullfile(p.control, 'srf_pll')), addpath(fullfile(p.control, 'srf_pll')); end

% Keep Simulink's caches out of OneDrive (same idea as TestHarness/setupHarness).
cache = fullfile(getenv('LOCALAPPDATA'), 'IntegrationSandbox', 'cache');
if ~isfolder(cache), mkdir(cache); end
Simulink.fileGenControl('set', 'CacheFolder',cache, 'CodeGenFolder',cache, 'createDir',true);
end
