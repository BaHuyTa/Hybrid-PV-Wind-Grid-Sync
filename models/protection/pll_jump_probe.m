function pll_jump_probe()
%PLL_JUMP_PROBE Frequency excursion when the PLL re-locks after a phase jump.
%   SC4 requires the PLL to re-lock within 100 ms after a 30 degree phase
%   jump. While it re-locks the frequency estimate moves, and if it leaves
%   47-52 Hz the anti-islanding relay would trip on a legitimate grid
%   disturbance. This measures how long that excursion lasts, which sets
%   the floor for the relay's persistence delay.

root = 'S:\UTS_Y4_S2\41088 - Professional Studio A';
addpath(genpath(fullfile(root,'models')));
load_system(fullfile(root,'models','control','srf_pll','srfPllLib.slx'));

mdl = 'pll_jump_probe_mdl';
if bdIsLoaded(mdl), close_system(mdl,0); end
new_system(mdl);  load_system(mdl);
Ts = 1e-4;  Vpk = 326.5986;  tJump = 0.5;

% phase = w*t + jump*step(t - tJump), built as a sine of an explicit angle
add_block('simulink/Sources/Clock',[mdl '/Clk']);
add_block('simulink/Sources/Step',[mdl '/Jmp'], ...
    'Time',num2str(tJump),'Before','0','After','jump_rad','SampleTime','0');
add_block('simulink/Math Operations/Gain',[mdl '/W'],'Gain','2*pi*50');
add_block('simulink/Math Operations/Sum',[mdl '/Sum'],'Inputs','++');
add_block('simulink/Signal Routing/Mux',[mdl '/Mx'],'Inputs','3');
for k = 1:3
    nm = sprintf('%s/Ph%d',mdl,k);
    add_block('simulink/Math Operations/Bias',nm,'Bias',sprintf('%.16g',-(k-1)*2*pi/3));
    add_block('simulink/Math Operations/Trigonometric Function', ...
        sprintf('%s/Sin%d',mdl,k),'Operator','sin');
    add_block('simulink/Math Operations/Gain', ...
        sprintf('%s/A%d',mdl,k),'Gain',num2str(Vpk));
end
add_block('srfPllLib/SRF_PLL',[mdl '/PLL'], ...
    'Ts',num2str(Ts),'f0','50','fbw','25','zeta','0.707');

add_line(mdl,'Clk/1','W/1');
add_line(mdl,'W/1','Sum/1');
add_line(mdl,'Jmp/1','Sum/2');
for k = 1:3
    add_line(mdl,'Sum/1',sprintf('Ph%d/1',k));
    add_line(mdl,sprintf('Ph%d/1',k),sprintf('Sin%d/1',k));
    add_line(mdl,sprintf('Sin%d/1',k),sprintf('A%d/1',k));
    add_line(mdl,sprintf('A%d/1',k),sprintf('Mx/%d',k));
end
add_line(mdl,'Mx/1','PLL/1');

ph = get_param([mdl '/PLL'],'PortHandles');
set_param(ph.Outport(2),'DataLogging','on', ...
    'DataLoggingNameMode','Custom','DataLoggingName','f_hz');
set_param(mdl,'SignalLogging','on','SignalLoggingName','logsout', ...
    'StopTime','1.0','SolverType','Fixed-step','Solver','ode4', ...
    'FixedStep',num2str(Ts/10));

fprintf('\n%8s %8s %8s %14s\n','jump','min Hz','max Hz','out of band');
fprintf('%s\n',repmat('-',1,44));
for jd = [10 20 30 45 60]
    assignin('base','jump_rad',jd*pi/180);
    out = sim(mdl);
    f = out.logsout.get('f_hz');
    t = double(f.Values.Time);  v = double(f.Values.Data);
    m = t >= tJump;                      % only the post-jump excursion
    tv = t(m);  vv = v(m);
    bad = vv < 47 | vv > 52;
    if any(bad)
        dur = tv(find(bad,1,'last')) - tJump;
    else
        dur = 0;
    end
    fprintf('%6d deg %8.2f %8.2f %10.1f ms\n', jd, min(vv), max(vv), 1000*dur);
end
fprintf('%s\n',repmat('-',1,44));
close_system(mdl,0);
end
