function pll_startup_probe()
%PLL_STARTUP_PROBE Worst-case duration of the PLL startup excursion.
%   Sweeps the initial phase offset of the grid source across a full cycle
%   and records how long the PLL frequency estimate stays outside the
%   47-52 Hz trip band. The maximum sets the floor for any startup blocking
%   or persistence delay in the anti-islanding relay.

root = 'S:\UTS_Y4_S2\41088 - Professional Studio A';
addpath(genpath(fullfile(root,'models')));
load_system(fullfile(root,'models','control','srf_pll','srfPllLib.slx'));

mdl = 'pll_startup_probe_mdl';
if bdIsLoaded(mdl), close_system(mdl,0); end
new_system(mdl);  load_system(mdl);
Ts = 1e-4;  Vpk = 326.5986;

add_block('simulink/Sources/Sine Wave',[mdl '/Vsrc'], ...
    'Amplitude',num2str(Vpk),'Frequency','2*pi*50', ...
    'Phase','[ph0, ph0-2*pi/3, ph0+2*pi/3]','SampleTime','0');
add_block('srfPllLib/SRF_PLL',[mdl '/PLL'], ...
    'Ts',num2str(Ts),'f0','50','fbw','25','zeta','0.707');
add_line(mdl,'Vsrc/1','PLL/1');

ph = get_param([mdl '/PLL'],'PortHandles');
set_param(ph.Outport(2),'DataLogging','on', ...
    'DataLoggingNameMode','Custom','DataLoggingName','f_hz');
set_param(mdl,'SignalLogging','on','SignalLoggingName','logsout', ...
    'StopTime','0.4','SolverType','Fixed-step','Solver','ode4', ...
    'FixedStep',num2str(Ts/10));

deg = 0:15:345;
last = zeros(size(deg));  lo = last;  hi = last;
for k = 1:numel(deg)
    assignin('base','ph0',deg(k)*pi/180);
    out = sim(mdl);
    f = out.logsout.get('f_hz');
    t = double(f.Values.Time);  v = double(f.Values.Data);
    bad = v < 47 | v > 52;
    if any(bad), last(k) = t(find(bad,1,'last')); end
    lo(k) = min(v);  hi(k) = max(v);
end

fprintf('\n%6s %8s %8s %12s\n','phase','min Hz','max Hz','settles by');
fprintf('%s\n',repmat('-',1,38));
for k = 1:numel(deg)
    fprintf('%4d deg %7.2f %8.2f %9.1f ms\n', deg(k), lo(k), hi(k), 1000*last(k));
end
fprintf('%s\n',repmat('-',1,38));
[w,i] = max(last);
fprintf('WORST: %.1f ms at %d deg (range %.2f to %.2f Hz)\n', ...
    1000*w, deg(i), min(lo), max(hi));
fprintf('\nfloor for a blocking/persistence delay: > %.0f ms\n', 1000*w);
fprintf('recommended with margin: block until 200 ms, pickup 100 ms\n');
close_system(mdl,0);
end
