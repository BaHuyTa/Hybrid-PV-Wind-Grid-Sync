%% run_pv_plots.m
% Reusable visualiser for the PV subsystem (solarsimulink).
%   1) Runs standard test conditions and saves a clean, labelled 4-panel figure.
%   2) Runs a quick irradiance sweep (standard + cloudy) and prints a summary.
%
% Usage: open solarsimulink, then press Run on this file (or type run_pv_plots).

model  = 'solarsimulink';
load_system(model);
Gconst = [model '/Constant'];      % irradiance source, W/m^2

%% ---------- 1. Standard conditions: clean 4-panel figure ----------
set_param(Gconst,'Value','1000');
set_param(model,'StopTime','0.5');
so = sim(model);

Vpv  = so.logsout.get('Vpv').Values;
Ipv  = so.logsout.get('Ipv').Values;
Vdc  = so.logsout.get('Vdc').Values;
Duty = so.logsout.get('Duty').Values;

ss  = Vpv.Time > 0.4;                                  % steady-state window
Pkw = mean(Vpv.Data(ss)) * mean(Ipv.Data(ss)) / 1000; % kW

f   = figure('Color','w','Position',[80 80 1000 780]);
col = [0.15 0.4 0.8];

subplot(4,1,1); plot(Vpv.Time,Vpv.Data,'LineWidth',1.3,'Color',col); grid on;
ylim([0 450]); ylabel('V_{pv} (V)');
title('Panel Voltage - MPPT holds \approx360 V (max-power point)');

subplot(4,1,2); plot(Ipv.Time,Ipv.Data,'LineWidth',1.3,'Color',col); grid on;
ylim([0 360]); ylabel('I_{pv} (A)');
title(sprintf('Panel Current - \\approx%.0f A   (P \\approx %.0f kW)', mean(Ipv.Data(ss)), Pkw));

subplot(4,1,3); plot(Vdc.Time,Vdc.Data,'LineWidth',1.3,'Color',col); grid on;
ylim([0 760]); ylabel('V_{dc} (V)');
title('Boost Output - placeholder load, NOT the real bus');
yl = yline(700,'--r','Real 700 V bus = inverter''s job');
yl.LabelHorizontalAlignment = 'left'; yl.FontSize = 8;

subplot(4,1,4); plot(Duty.Time,Duty.Data,'LineWidth',1.3,'Color',col); grid on;
ylim([0 1]); ylabel('Duty'); xlabel('Time (s)');
title('Duty Cycle - set by the PI loop');

sgtitle('PV Subsystem @ 1000 W/m^2, 25\circC','FontWeight','bold');

pngpath = fullfile(fileparts(which(model)),'pv_results.png');
exportgraphics(f, pngpath, 'Resolution', 150);
fprintf('Saved figure: %s\n', pngpath);

%% ---------- 2. Irradiance sweep: SUNNY vs CLOUDY comparison ----------
Gs     = [1000 600 300];
labels = {'1000 W/m^2 (sunny)','600 W/m^2 (cloudy)','300 W/m^2 (low light)'};
cols   = [0.95 0.60 0.10; 0.20 0.50 0.85; 0.35 0.35 0.40];   % gold / blue / grey
data   = cell(numel(Gs),1);

fprintf('\nIrradiance sweep (25 C):\n');
fprintf('  G(W/m^2)   Vpv(V)   Ipv(A)    P(kW)\n');
for k = 1:numel(Gs)
    set_param(Gconst,'Value',num2str(Gs(k)));
    s = sim(model);
    v = s.logsout.get('Vpv').Values;
    i = s.logsout.get('Ipv').Values;
    data{k} = struct('t',v.Time,'V',v.Data,'I',i.Data,'P',v.Data.*i.Data/1000);
    w = v.Time > 0.32;
    fprintf('  %6d    %6.1f   %6.1f   %6.1f\n', ...
            Gs(k), mean(v.Data(w)), mean(i.Data(w)), mean(v.Data(w))*mean(i.Data(w))/1000);
end
set_param(Gconst,'Value','1000');   % restore standard conditions

% Comparison figure: power (top) and panel voltage (bottom), all cases overlaid
g = figure('Color','w','Position',[120 120 950 640]);

subplot(2,1,1); hold on; grid on;
for k = 1:numel(Gs), plot(data{k}.t, data{k}.P, 'LineWidth',1.6,'Color',cols(k,:)); end
ylabel('Power (kW)'); ylim([0 130]); legend(labels,'Location','east');
title('Sunny vs Cloudy - more sunlight = more power');

subplot(2,1,2); hold on; grid on;
for k = 1:numel(Gs), plot(data{k}.t, data{k}.V, 'LineWidth',1.6,'Color',cols(k,:)); end
ylabel('Panel Voltage (V)'); xlabel('Time (s)'); ylim([0 450]); legend(labels,'Location','east');
title('...but MPPT holds the panel near its best voltage (\approx350-360 V) in every case');

cmp = fullfile(fileparts(which(model)),'pv_sunny_vs_cloudy.png');
exportgraphics(g, cmp, 'Resolution',150);
fprintf('\nSaved comparison figure: %s\n', cmp);
fprintf('Done.\n');
