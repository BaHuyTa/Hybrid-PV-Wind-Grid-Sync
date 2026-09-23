%% run_pv_plots.m
% PV subsystem: test harness + plots, in one place. Run this file and it:
%   1) Runs all 4 scenarios (3 standard irradiance levels @ 25C + hot day @ 65C)
%   2) Prints a pass/fail table + temperature-physics sanity check
%   3) Overwrites pv_results.png (single-condition detail) and
%      pv_comparison.png (all scenarios overlaid, incl. bus voltage)
%
% Every run regenerates both PNGs from scratch -- there is no stale output
% left behind; whatever's in this folder after running reflects the
% model's CURRENT state, not some earlier version.
%
% Scenario 4 (65C) needs ~3s to settle -- the cascaded P&O/PI controller
% has to walk much further from its fixed 360V starting guess than the
% 25C cases do. Don't shorten its StopTime without re-checking convergence
% (see the "settled" check below) -- a short run here looks like a bug
% but isn't one; it's just mid-transient.
%
% Bus side: output feeds an ideal 700V source (Hoang's fix) -- a
% standalone-test stand-in for "wherever this connects to will be held at
% 700V". This proves the converter behaves correctly feeding a stiff
% 700V rail. It does NOT prove the real multi-source bus holds 700V --
% that's still Aqib/Duc's DC-link control loop, not solved here.

model  = 'solarsimulink';
load_system(model);
Gconst = [model '/Constant'];
panel  = [model '/Solar Panel'];
outdir = fileparts(which(model));

% All scenarios run for the SAME duration (3s, the longest one needs) so
% every line spans the full comparison plot -- the 25C cases settle well
% before 3s and just hold flat for the rest, which is fine and expected.
SETTLE_T = 3.0;
scenarios = { ...
  'Standard (1000 W/m2, 25C)',  1000, 25, SETTLE_T, [0.90 0.55 0.10]; ...
  'Cloudy (600 W/m2, 25C)',      600, 25, SETTLE_T, [0.20 0.50 0.85]; ...
  'Low light (300 W/m2, 25C)',   300, 25, SETTLE_T, [0.35 0.35 0.40]; ...
  'Hot day (1000 W/m2, 65C)',   1000, 65, SETTLE_T, [0.80 0.15 0.15]; ...
};
nS = size(scenarios,1);
data = cell(nS,1);
results = struct('name',{},'Vpv',{},'Ipv',{},'P_kW',{},'Vdc',{},'settled',{},'pass',{},'notes',{});

fprintf('%-30s %8s %8s %8s %8s\n','Scenario','Vpv(V)','P(kW)','Vdc(V)','PASS?');
fprintf('%s\n', repmat('-',1,66));

for k = 1:nS
    name = scenarios{k,1}; G = scenarios{k,2}; T = scenarios{k,3}; settle_t = scenarios{k,4};

    set_param(Gconst,'Value',num2str(G));
    set_param(panel,'CellTempC',num2str(T));

    % v_dc is a real external input port (matching Huy's windPlantSw.slx
    % pattern -- DC_link is a Controlled Voltage Source fed from outside,
    % not a value hardcoded in the model). Feed it here the same way his
    % windSim.m does, via a SimulationInput dataset.
    ds = Simulink.SimulationData.Dataset;
    ds = ds.addElement(timeseries([700 700], [0 settle_t]), 'v_dc');
    in = Simulink.SimulationInput(model);
    in = in.setModelParameter('StopTime', num2str(settle_t), ...
                               'LoadExternalInput','on', 'ExternalInput','ds');
    in = in.setVariable('ds', ds);
    so = sim(in);

    Vpv = so.logsout.get('Vpv').Values; Ipv = so.logsout.get('Ipv').Values;
    Vdc = so.logsout.get('Vdc').Values; D   = so.logsout.get('Duty').Values;
    data{k} = struct('t',Vpv.Time,'V',Vpv.Data,'I',Ipv.Data,'Vdc',Vdc.Data,'D',D.Data);

    tt = Vpv.Time;
    win = tt > 0.9*settle_t; win_prev = tt > 0.8*settle_t & tt <= 0.9*settle_t;
    v = mean(Vpv.Data(win)); i = mean(Ipv.Data(win)); vdc = mean(Vdc.Data(win)); d = mean(D.Data(win));
    v_prev = mean(Vpv.Data(win_prev));
    settled = abs(v - v_prev) < 1.0;
    bus_ok = abs(vdc - 700) <= 35;
    finite_ok = all(isfinite([v i vdc d])) && d > 0.03 && d < 0.97;
    pass = bus_ok && finite_ok && settled;
    notes = {};
    if ~settled, notes{end+1} = 'NOT SETTLED - extend StopTime'; end
    if ~bus_ok,  notes{end+1} = sprintf('Vdc %.1fV outside 700+-5%%', vdc); end

    results(k) = struct('name',name,'Vpv',v,'Ipv',i,'P_kW',v*i/1000,'Vdc',vdc,'settled',settled,'pass',pass,'notes',{notes});
    fprintf('%-30s %8.1f %8.1f %8.1f %8s\n', name, v, v*i/1000, vdc, string(pass));
end

%% Temperature sanity check
i25 = 1; i65 = 4;   % Standard vs Hot day, by index
p25 = results(i25).P_kW; p65 = results(i65).P_kW;
v25 = results(i25).Vpv;  v65 = results(i65).Vpv;
loss_pct = (p25 - p65)/p25*100;
volt_dir_ok = v65 < v25;
temp_pass = (loss_pct >= 10 && loss_pct <= 25) && volt_dir_ok;
if volt_dir_ok, dirmsg = 'decreased, correct'; else, dirmsg = 'INCREASED - WRONG'; end

fprintf('\n--- Temperature sanity check (25C -> 65C) ---\n');
fprintf('Power:   %.1f kW -> %.1f kW  (%.1f%% loss, expect 15-20%%)\n', p25, p65, loss_pct);
fprintf('Voltage: %.1f V  -> %.1f V   (%s)\n', v25, v65, dirmsg);
fprintf('Temperature physics: %s\n', string(temp_pass));

fprintf('\n=== SUMMARY ===\n');
allpass = temp_pass;
for k=1:nS
    fprintf('%-30s : %s\n', results(k).name, string(results(k).pass));
    for n = results(k).notes, fprintf('    - %s\n', n{1}); end
    allpass = allpass && results(k).pass;
end
fprintf('Temperature physics check         : %s\n', string(temp_pass));
fprintf('ALL CHECKS PASS: %s\n', string(allpass));

%% ---------- Figure 1: standard-conditions detail ----------
d1 = data{1}; col = [0.15 0.4 0.8];
f1 = figure('Color','w','Position',[80 80 1000 780]);

subplot(4,1,1); plot(d1.t,d1.V,'LineWidth',1.3,'Color',col); grid on;
ylim([0 450]); ylabel('V_{pv} (V)'); title(sprintf('Panel Voltage - settles \\approx%.0f V (max-power point)', results(1).Vpv));

subplot(4,1,2); plot(d1.t,d1.I,'LineWidth',1.3,'Color',col); grid on;
ylim([0 360]); ylabel('I_{pv} (A)'); title(sprintf('Panel Current - \\approx%.0f A (P \\approx %.1f kW)', results(1).Ipv, results(1).P_kW));

subplot(4,1,3); plot(d1.t,d1.Vdc,'LineWidth',1.3,'Color',col); grid on;
ylim([0 800]); ylabel('V_{dc} (V)'); title('Boost Output - pinned at 700V bus test fixture');
yl = yline(700,'--r','700V bus'); yl.LabelHorizontalAlignment='left'; yl.FontSize=8;

subplot(4,1,4); plot(d1.t,d1.D,'LineWidth',1.3,'Color',col); grid on;
ylim([0 1]); ylabel('Duty'); xlabel('Time (s)'); title('Duty Cycle');

sgtitle('PV Subsystem @ 1000 W/m^2, 25\circC','FontWeight','bold');
p1 = fullfile(outdir,'pv_results.png');
exportgraphics(f1, p1, 'Resolution', 150);
fprintf('\nSaved: %s\n', p1);

%% ---------- Figure 2: all scenarios compared ----------
labels = scenarios(:,1); cols = cell2mat(scenarios(:,5));
f2 = figure('Color','w','Position',[120 120 1000 820]);

subplot(3,1,1); hold on; grid on;
for k=1:nS, plot(data{k}.t, data{k}.V.*data{k}.I/1000, 'LineWidth',1.6,'Color',cols(k,:)); end
ylabel('Power (kW)'); ylim([0 130]); legend(labels,'Location','east');
title('Power across conditions - sunlight and temperature both matter');

subplot(3,1,2); hold on; grid on;
for k=1:nS, plot(data{k}.t, data{k}.V, 'LineWidth',1.6,'Color',cols(k,:)); end
ylabel('Panel Voltage (V)'); ylim([0 450]); legend(labels,'Location','east');
title('Panel voltage - MPPT tracks the (correctly temperature-dependent) best point in every case');

subplot(3,1,3); hold on; grid on;
for k=1:nS, plot(data{k}.t, data{k}.Vdc, 'LineWidth',1.6,'Color',cols(k,:)); end
yline(700,'--k','700V target');
ylabel('V_{dc} (V)'); xlabel('Time (s)'); ylim([0 800]); legend(labels,'Location','east');
title('Bus output - pinned at 700V in every scenario (test fixture, see header notes)');

sgtitle('PV Subsystem - all test scenarios','FontWeight','bold');
p2 = fullfile(outdir,'pv_comparison.png');
exportgraphics(f2, p2, 'Resolution', 150);
fprintf('Saved: %s\n', p2);

%% restore defaults
set_param(Gconst,'Value','1000');
set_param(panel,'CellTempC','25');
set_param(model,'StopTime','0.5');
fprintf('\nDone. Model restored to standard-condition defaults.\n');
