classdef LiveDemo < handle
%LIVEDEMO  Roadshow app: the integration results, replayed as if live.
%
%   LiveDemo                            full screen; the real day starts looping
%   app = LiveDemo(Window=[50 50 1600 900])
%
% Nothing is simulated here. One second of the full switching model takes minutes
% to simulate, so every case was run beforehand (exportDemoPack -> demoPack.mat)
% and this app switches to the matching run instantly and plays it back.
%
%   Idle        the real day (Gullen Range NSW, 6 Oct 2026, 06:00-14:00) loops,
%               about a minute per loop. The load slider swaps between the three
%               day runs at the same clock time.
%   Buttons     grid fault (dip), load shed, grid lost (island). Each plays its
%               run in slow motion around the event, shows the measured result,
%               and goes back to the day on its own.
%
% Keys: 1 2 3  load 50 / 150 / 250 kW     F  grid fault     S  load shed
%       I      grid lost (island)          A  anti-islanding (SFS) on/off
%       B, Esc back to the day             Space  pause      Right arrow  skip ahead
%       F11    full screen
%
% Needs base MATLAB only (no Simulink): the runs are in demoPack.mat. The look is
% plain App Designer defaults: grey window, titled panels, standard controls,
% MATLAB's default line colours.

    properties
        Pack                    % from exportDemoPack
        Fig
        UI      = struct()
        Mode    = "day"         % "day" | "event"
        Run                     % the run on screen
        t       = 0             % playhead, simulation seconds
        Load    = 150           % kW
        Sfs     = true
        Paused  = false
        DayT    = 0.25          % where the day loop picks up again after an event
        Hold    = 0             % seconds spent on the result at the end of an event
        Segs    = []            % event playback speeds: [t0 t1 rate] rows, sim s per wall s
        Tm                      % timer
        Last                    % tic of the previous frame
        HoldEnd = 10            % seconds the result stays up before the day resumes
        Errors  = 0
        Frames  = 0             % frames drawn (app.Frames / seconds = frame rate)
    end

    properties (Constant)
        FPS      = 25
        DAY0     = 0.25         % skip start-up (06:00-06:25)
        DAY_WALL = 60           % seconds on screen per loop of the day
        LOADS    = [50 150 250]
        % MATLAB's default line colours
        BLUE   = [0 0.4470 0.7410]
        ORANGE = [0.8500 0.3250 0.0980]
        YELLOW = [0.9290 0.6940 0.1250]
        GREEN  = [0.4660 0.6740 0.1880]
        RED    = [1 0 0]
        GREY   = [0.5 0.5 0.5]
    end

    methods
        function app = LiveDemo(opts)
            arguments
                opts.Pack   (1,1) string  = ""
                opts.Window double        = []        % [x y w h]; empty = full screen
                opts.Start  (1,1) logical = true      % false: no timer (recording, tests)
            end
            here = fileparts(mfilename('fullpath'));
            if opts.Pack == "", opts.Pack = fullfile(here, "demoPack.mat"); end
            if ~isfile(opts.Pack)
                error('LiveDemo:noPack', ['%s not found. Make it with exportDemoPack ' ...
                      '(after the runs exist), or pull it from the repo.'], opts.Pack);
            end
            S = load(opts.Pack, 'pack');  app.Pack = S.pack;
            for k = 1:numel(app.Pack.runs)
                app.Pack.runs(k).oob = LiveDemo.oobRun(app.Pack.runs(k), app.Pack.lim);
            end
            app.build(opts.Window);
            app.showDay();
            app.Tm = timer('ExecutionMode','fixedSpacing', 'Period',round(1/app.FPS, 3), ...
                'BusyMode','drop', 'TimerFcn',@(~,~) app.tick(), 'Name','LiveDemo');
            if opts.Start, app.Last = tic; start(app.Tm); end
        end

        %% ---- what the buttons and keys do --------------------------------
        function setLoad(app, L)
            [~, j] = min(abs(app.LOADS - L));  L = app.LOADS(j);
            app.Load = L;  app.UI.slider.Value = L;
            if app.Mode == "day"
                app.Run = app.runFor("day", L);  app.render();
            elseif ismember(app.Run.kind, ["dip","shed"])
                app.playEvent(app.Run.kind);            % same event, the other load's run
            end
        end

        function setSfs(app, on)
            app.Sfs = logical(on);
            app.UI.sfs.Value = tern(app.Sfs, 'On', 'Off');
            if app.Mode == "event" && app.Run.kind == "island", app.playEvent("island"); end
        end

        function playEvent(app, kind)
            if kind == "island", u = app.runFor("island", NaN, app.Sfs);
            else,                u = app.runFor(kind, app.Load);
            end
            if isempty(u), app.UI.relay.Value = 'Run not in demoPack.mat'; return; end
            if app.Mode == "day", app.DayT = app.t; end
            app.Mode = "event";  app.Run = u;  app.Hold = 0;
            te = u.t_event;
            switch kind      % slow motion around what matters, quicker before and after
                case "dip",  slow = [te-0.03, u.t_clear+0.12];  after = 1/6;
                case "shed", slow = [te-0.02, te+0.10];         after = 1/6;
                otherwise
                    if isfinite(u.t_trip) && u.t_trip < u.T, slow = [te-0.02, u.t_trip+0.05];  after = 1/6;
                    else,                                     slow = [te-0.02, te+0.15];        after = 1/2;
                    end
            end
            app.Segs = [te-0.1, slow(1), 1/6; slow(1), slow(2), 1/25; slow(2), u.T, after];
            app.t = te - 0.1;
            app.layoutFor(u);  app.render();
        end

        function showDay(app)
            app.Mode = "day";  app.Run = app.runFor("day", app.Load);  app.t = app.DayT;
            if ~app.Sfs, app.setSfs(true); end      % the next group starts from the real design
            app.layoutFor(app.Run);  app.render();
        end

        function togglePause(app)
            app.Paused = ~app.Paused;  app.render();
        end

        function skip(app)
            if app.Mode == "day", app.t = min(app.Run.T, app.t + app.Run.T/8);
            else, app.t = app.Run.T;
            end
            app.render();
        end

        function frame(app, t)
        % Draw the screen at simulation time t (recording and tests).
            app.t = t;  app.render();
        end

        function advance(app, dtw)
        % Move the playhead by dtw seconds of wall time.
            u = app.Run;
            if app.Mode == "day"
                app.t = app.t + dtw*(u.T - app.DAY0)/app.DAY_WALL;
                if app.t > u.T, app.t = app.DAY0; end
            elseif app.t >= u.T
                app.Hold = app.Hold + dtw;
                if app.Hold > app.HoldEnd, app.showDay(); end
            else
                app.t = min(u.T, app.t + dtw*app.rate());
            end
        end

        function delete(app)
            if ~isempty(app.Tm) && isvalid(app.Tm), stop(app.Tm); delete(app.Tm); end
            if ~isempty(app.Fig) && isvalid(app.Fig), delete(app.Fig); end
        end
    end

    methods (Access = private)
        function tick(app)
            try
                dtw = min(toc(app.Last), 0.2);  app.Last = tic;
                if app.Paused, return; end
                app.advance(dtw);  app.render();
            catch err
                % Keep going at the table: report, fall back to the day loop, and only
                % give up if it keeps failing.
                app.Errors = app.Errors + 1;
                fprintf(2, 'LiveDemo: %s\n', err.message);
                if app.Errors > 20, stop(app.Tm); fprintf(2, 'LiveDemo stopped after 20 errors.\n');
                elseif app.Mode == "event", try app.showDay(); catch, end
                end
            end
        end

        function r = rate(app)
            k = find(app.t >= app.Segs(:,1) & app.t < app.Segs(:,2), 1);
            if isempty(k), r = app.Segs(end,3); else, r = app.Segs(k,3); end
        end

        function u = runFor(app, kind, L, sfs)
            R = app.Pack.runs;  m = [R.kind] == kind;
            if kind == "island", m = m & [R.sfs] == sfs;
            else,                m = m & [R.load] == L;
            end
            u = R(find(m, 1));
        end

        function key(app, e)
            switch lower(e.Key)
                case {'1','numpad1'}, app.setLoad(50);
                case {'2','numpad2'}, app.setLoad(150);
                case {'3','numpad3'}, app.setLoad(250);
                case 'f', app.playEvent("dip");
                case 's', app.playEvent("shed");
                case 'i', app.playEvent("island");
                case 'a', app.setSfs(~app.Sfs);
                case {'b','escape'}, if app.Mode == "event", app.showDay(); end
                case 'space', app.togglePause();
                case 'rightarrow', app.skip();
                case 'f11', app.Fig.WindowState = tern(app.Fig.WindowState == "fullscreen", 'maximized', 'fullscreen');
            end
        end

        %% ---- the window -------------------------------------------------
        function build(app, win)
            f = uifigure('Name','Hybrid PV-Wind System with Grid Synchronisation', 'Visible','off');
            if isempty(win), f.WindowState = 'maximized'; else, f.Position = win; end
            try theme(f, "light"); catch, end         % R2025a+ follows the OS theme otherwise
            f.CloseRequestFcn   = @(~,~) delete(app);
            f.WindowKeyPressFcn = @(~,e) app.key(e);
            app.Fig = f;
            scr = get(groot, 'ScreenSize');  H = scr(4);  if ~isempty(win), H = win(4); end
            cmp = H < 1000;  z = @(big, small) tern(cmp, small, big);   % short screens
            fs  = z(14, 12);                                            % control font size

            g = uigridlayout(f, [2 2], 'RowHeight',{z(40,30),'1x'}, 'ColumnWidth',{z(330,290),'1x'}, ...
                'Padding',[10 10 10 10], 'RowSpacing',z(8,4), 'ColumnSpacing',10);
            t = uilabel(g, 'Text','Hybrid PV-Wind System with Grid Synchronisation', ...
                'FontSize',z(22,18), 'FontWeight','bold', 'HorizontalAlignment','center');
            t.Layout.Row = 1;  t.Layout.Column = [1 2];

            left = uigridlayout(g, [4 1], 'RowHeight',{'fit','fit','fit','1x'}, 'Padding',0, 'RowSpacing',z(8,4));
            left.Layout.Row = 2;  left.Layout.Column = 1;

            % Controls
            pc = uipanel(left, 'Title','Controls', 'FontSize',fs);
            c  = uigridlayout(pc, [7 2], 'RowHeight',{z(22,18), z(46,38), z(36,26), z(36,26), z(36,26), z(30,24), z(36,26)}, ...
                'ColumnWidth',{'1x','1x'}, 'RowSpacing',z(8,4), 'Padding',z([10 8 10 10],[8 4 8 6]));
            l = uilabel(c, 'Text','Factory load (kW)', 'FontSize',fs);  LiveDemo.at(l, 1, [1 2]);
            app.UI.slider = uislider(c, 'Limits',[50 250], 'MajorTicks',app.LOADS, 'MinorTicks',[], ...
                'Value',app.Load, 'FontSize',fs, 'ValueChangedFcn',@(~,e) app.setLoad(e.Value));
            LiveDemo.at(app.UI.slider, 2, [1 2]);
            app.UI.bDip  = app.button(c, 3, 'Grid Fault', @() app.playEvent("dip"),    fs);
            app.UI.bShed = app.button(c, 4, 'Load Shed',  @() app.playEvent("shed"),   fs);
            app.UI.bIsl  = app.button(c, 5, 'Grid Lost',  @() app.playEvent("island"), fs);
            LiveDemo.at(uilabel(c, 'Text','Anti-islanding (SFS)', 'FontSize',fs), 6, 1);
            app.UI.sfs = uiswitch(c, 'slider', 'Items',{'Off','On'}, 'Value','On', 'FontSize',fs, ...
                'ValueChangedFcn',@(~,e) app.setSfs(e.Value == "On"));
            LiveDemo.at(app.UI.sfs, 6, 2);
            app.UI.bDay = app.button(c, 7, 'Back to Day', @() app.showDay(), fs);

            % Measurements
            pm = uipanel(left, 'Title','Measurements', 'FontSize',fs);
            lab = ["Irradiance (W/m²)","Wind speed (m/s)","PV (kW)","Wind (kW)","Output (kW)","Load (kW)","Grid (kW)"];
            m  = uigridlayout(pm, [numel(lab) 2], 'RowHeight',repmat({z(26,20)},1,numel(lab)), ...
                'ColumnWidth',{'1x',z(130,110)}, 'RowSpacing',z(6,2), 'Padding',z([10 8 10 10],[8 4 8 6]));
            for j = 1:numel(lab)
                uilabel(m, 'Text',lab(j), 'FontSize',fs);
                app.UI.num(j) = uieditfield(m, 'text', 'Editable','off', 'FontSize',fs, ...
                    'HorizontalAlignment','right');
            end

            % Status
            ps = uipanel(left, 'Title','Status', 'FontSize',fs);
            s  = uigridlayout(ps, [5 3], 'RowHeight',{z(26,20), z(26,20), z(26,20), z(96,58), z('fit',0)}, ...
                'ColumnWidth',{z(90,70), 22, '1x'}, 'RowSpacing',z(6,3), 'Padding',z([10 8 10 10],[8 4 8 6]));
            app.UI.caseF = LiveDemo.field(s, 1, 'Case', fs);
            app.UI.time  = LiveDemo.field(s, 2, 'Time', fs);
            LiveDemo.at(uilabel(s, 'Text','Relay', 'FontSize',fs), 3, 1);
            app.UI.lamp  = uilamp(s);  LiveDemo.at(app.UI.lamp, 3, 2);
            app.UI.relay = uieditfield(s, 'text', 'Editable','off', 'FontSize',fs);
            LiveDemo.at(app.UI.relay, 3, 3);
            app.UI.card  = uitextarea(s, 'Editable','off', 'FontSize',fs, 'Value',{''});
            app.UI.card.Layout.Row = 4;  app.UI.card.Layout.Column = [1 3];
            n = uilabel(s, 'Text','Replay of saved switching-model runs (0.5 µs step)', ...
                'FontSize',z(12,11), 'FontColor',[0.4 0.4 0.4], 'WordWrap','on');
            n.Layout.Row = 5;  n.Layout.Column = [1 3];

            % Plots
            p = uigridlayout(g, [2 2], 'Padding',0, 'RowSpacing',z(10,6), 'ColumnSpacing',10);
            p.Layout.Row = 2;  p.Layout.Column = 2;
            A.pow = LiveDemo.mkAxes(p, "pow", 'Power', 'Power (kW)');
            A.bus = LiveDemo.mkAxes(p, "bus", 'DC Bus Voltage', 'Voltage (V)');
            A.sco = LiveDemo.mkAxes(p, "sco", 'PCC Voltage and Current (Phase A)', '');
            A.pll = LiveDemo.mkAxes(p, "pll", 'PLL Frequency', 'Frequency (Hz)');
            for ax = [A.pow A.bus A.pll]
                % event markers (event mode only): fault shading, event line, trip line; day cursor
                L.(ax.Tag + "Shade") = patch(ax, [0 0 0 0], [-1e4 -1e4 1e4 1e4], [0.85 0.85 0.85], ...
                    'EdgeColor','none', 'FaceAlpha',0.6, 'Visible','off', 'HandleVisibility','off');
                L.(ax.Tag + "Ev")    = line(ax, [0 0], [-1e4 1e4], 'Color','k', 'LineStyle','--', 'Visible','off', 'HandleVisibility','off');
                L.(ax.Tag + "Trip")  = line(ax, [0 0], [-1e4 1e4], 'Color',app.RED, 'LineWidth',1.5, 'Visible','off', 'HandleVisibility','off');
                L.(ax.Tag + "Cur")   = line(ax, [0 0], [-1e4 1e4], 'Color',app.GREY, 'HandleVisibility','off');
            end
            lim = app.Pack.lim;  vr = lim.Vdc_ref;  lw = 1.5;
            % power
            L.ac   = line(A.pow, nan, nan, 'Color',app.BLUE,   'LineWidth',2);
            L.pv   = line(A.pow, nan, nan, 'Color',app.ORANGE, 'LineWidth',lw);
            L.wind = line(A.pow, nan, nan, 'Color',app.YELLOW, 'LineWidth',lw);
            L.load = line(A.pow, nan, nan, 'Color','k', 'LineWidth',lw, 'LineStyle','--');
            L.leg  = legend(A.pow, [L.ac L.pv L.wind L.load], {'Output','PV','Wind','Load'}, ...
                'Location','northwest', 'Orientation','horizontal', 'FontSize',z(12,10));
            % bus: +/-5 % band and, in a fault, the 800 V ride-through limit
            line(A.bus, [-1e4 1e4], vr*(1-lim.band)*[1 1], 'Color',app.RED, 'LineStyle','--', 'HandleVisibility','off');
            line(A.bus, [-1e4 1e4], vr*(1+lim.band)*[1 1], 'Color',app.RED, 'LineStyle','--', 'HandleVisibility','off');
            L.v800 = line(A.bus, [-1e4 1e4], lim.Vdc_max*[1 1], 'Color',app.RED, 'LineStyle','-.', 'HandleVisibility','off');
            L.vdc  = line(A.bus, nan, nan, 'Color',app.BLUE, 'LineWidth',lw);
            % scope: phase a of the PCC voltage (left axis) and our grid current (right)
            yyaxis(A.sco, 'left');   ylim(A.sco, [-420 420]);  ylabel(A.sco, 'Voltage (V)');
            L.va = line(A.sco, nan, nan, 'Color',app.BLUE, 'LineWidth',lw);
            yyaxis(A.sco, 'right');  ylim(A.sco, [-420 420]);  ylabel(A.sco, 'Current (A)');
            L.ia = line(A.sco, nan, nan, 'Color',app.ORANGE, 'LineWidth',lw);
            A.sco.YAxis(1).Color = app.BLUE;  A.sco.YAxis(2).Color = app.ORANGE;
            xlabel(A.sco, 'Time (ms)');
            % PLL: the 47-52 Hz relay band
            line(A.pll, [-1e4 1e4], lim.f_min*[1 1], 'Color',app.RED, 'LineStyle','--', 'HandleVisibility','off');
            line(A.pll, [-1e4 1e4], lim.f_max*[1 1], 'Color',app.RED, 'LineStyle','--', 'HandleVisibility','off');
            L.f    = line(A.pll, nan, nan, 'Color',app.BLUE, 'LineWidth',lw);
            L.lim2 = line(A.pll, [2000 2000], [-1e4 1e4], 'Color',app.RED, 'LineStyle',':', 'Visible','off', 'HandleVisibility','off');

            app.UI.ax = A;  app.UI.L = L;
            f.Visible = 'on';
        end

        function b = button(~, parent, row, txt, fcn, fs)
            b = uibutton(parent, 'Text',txt, 'FontSize',fs, 'ButtonPushedFcn',@(~,~) fcn());
            LiveDemo.at(b, row, [1 2]);
        end

        function layoutFor(app, u)
        % Axes ranges and markers for the day or for one event.
            A = app.UI.ax;  L = app.UI.L;
            day = app.Mode == "day";
            on  = @(c) tern(c, 'on', 'off');
            if day
                for ax = [A.pow A.bus A.pll]
                    xlim(ax, [6 14]);  ax.XTick = 6:14;
                    ax.XTickLabel = compose('%02d:00', (6:14)');
                    xlabel(ax, 'Time of day');
                end
                ylim(A.pow, [0 320]);  ylim(A.bus, [655 745]);  ylim(A.pll, [45 55]);
                xlim(A.sco, [0 40]);
            else
                xe = [-100, 1e3*(u.T - u.t_event)];
                for ax = [A.pow A.bus A.pll]
                    xlim(ax, xe);  ax.XTickMode = 'auto';  ax.XTickLabelMode = 'auto';
                    xlabel(ax, 'Time (ms)');
                end
                ylim(A.pow, [-20 320]);  ylim(A.pll, [40 62]);
                ylim(A.bus, tern(u.kind == "dip", [645 825], [655 745]));
            end
            L.v800.Visible = on(~day && u.kind == "dip");
            L.lim2.Visible = on(~day && u.kind == "island" && u.T > 2.2);
            for tg = ["pow","bus","pll"]
                L.(tg + "Shade").Visible = on(~day && u.kind == "dip");
                L.(tg + "Shade").XData   = [0 1 1 0]*1e3*(u.t_clear - u.t_event);
                L.(tg + "Ev").Visible    = on(~day);
                L.(tg + "Trip").Visible  = 'off';
                L.(tg + "Cur").Visible   = on(day);
            end
            if ~day && isfinite(u.t_trip) && u.t_trip < u.T
                for tg = ["pow","bus","pll"], L.(tg + "Trip").XData = 1e3*(u.t_trip - u.t_event)*[1 1]; end
            end
            L.leg.String{4} = char(tern(u.kind == "island", "Test load", "Load"));
            app.UI.slider.Enable = on(day || u.kind ~= "island");
            app.UI.bDay.Enable   = on(~day);
            switch u.kind
                case "day",    app.UI.caseF.Value = sprintf('Real day, %d kW load', u.load);
                case "dip",    app.UI.caseF.Value = sprintf('Grid fault, %d kW load', u.load);
                case "shed",   app.UI.caseF.Value = sprintf('Load shed, %d kW', u.load);
                case "island", app.UI.caseF.Value = char("Grid lost, SFS " + tern(u.sfs, "on", "off"));
            end
        end

        %% ---- one frame ---------------------------------------------------
        function render(app)
            u = app.Run;  L = app.UI.L;  lim = app.Pack.lim;  t = app.t;
            dS = double(u.tS(2) - u.tS(1));  dF = double(u.tF(2) - u.tF(1));
            k  = max(1, min(numel(u.tS), floor((t - double(u.tS(1)))/dS) + 1));
            kF = max(1, min(numel(u.tF), floor((t - double(u.tF(1)))/dF) + 1));
            day = app.Mode == "day";
            if day
                k0 = max(1, floor((app.DAY0 - double(u.tS(1)))/dS) + 1);
                i  = k0:k;   x = app.clockH(u.tS(i));
                xc = app.clockH(t);
            else
                i  = 1:k;    x = 1e3*(double(u.tS(i)) - u.t_event);
                xc = 1e3*(t - u.t_event);
            end
            set(L.pv,   'XData',x, 'YData',u.Ppv(i));
            set(L.wind, 'XData',x, 'YData',u.Pwind(i));
            set(L.ac,   'XData',x, 'YData',u.Pac(i));
            set(L.load, 'XData',x, 'YData',u.Pload(i));
            set(L.vdc,  'XData',x, 'YData',u.vdc(i));
            % After an island trip there is no voltage left for the PLL to lock on to:
            % its estimate just wanders, so the trace ends at the trip.
            iso = ~day && u.kind == "island" && isfinite(u.t_trip) && u.t_trip < u.T;
            jf  = true(size(i));  if iso, jf = u.tS(i) <= u.t_trip + 0.003; end
            set(L.f,    'XData',x(jf), 'YData',u.f(i(jf)));
            for tg = ["pow","bus","pll"], L.(tg + "Cur").XData = [xc xc]; end
            if ~day && isfinite(u.t_trip) && t >= u.t_trip
                for tg = ["pow","bus","pll"], L.(tg + "Trip").Visible = 'on'; end
            end

            % scope: on the day a triggered 40 ms (two cycles) window, so the trace
            % stands still; in an event a rolling 60 ms window, so you see it happen
            if day
                n = round(0.04/dF);  j = max(1, kF - 2*n);
                va = u.vabc(:,1);
                zc = find(va(j:max(j, kF-n)) < 0 & va(j+1:max(j+1, kF-n+1)) >= 0, 1, 'last');
                if isempty(zc), a = max(1, kF - n + 1); else, a = j + zc; end
                w = a:min(numel(u.tF), a + n - 1);  xs = 1e3*(w - a)*dF;
                xlim(app.UI.ax.sco, [0 40]);
            else
                n = round(0.06/dF);  w = max(1, kF - n + 1):kF;
                xs = 1e3*(double(u.tF(w)) - u.t_event);
                xlim(app.UI.ax.sco, [xs(end) - 60, xs(end) + 0.001]);
            end
            set(L.va, 'XData',xs, 'YData',u.vabc(w,1));
            set(L.ia, 'XData',xs, 'YData',u.iabc(w,1));

            % measurements
            N = app.UI.num;
            N(1).Value = sprintf('%.0f', u.G(k));
            N(2).Value = sprintf('%.1f', u.vw(k));
            N(3).Value = sprintf('%.1f', u.Ppv(k));
            N(4).Value = sprintf('%.1f', u.Pwind(k));
            N(5).Value = sprintf('%.1f', u.Pac(k));
            N(6).Value = sprintf('%.0f', u.Pload(k));
            infault = u.kind == "dip" && t >= u.t_event && t < u.t_clear;
            if ~u.grid_on(k),      N(7).Value = 'Disconnected';
            elseif infault,        N(7).Value = 'Fault';
            elseif u.Pgrid(k) >= 0, N(7).Value = sprintf('%.1f import', u.Pgrid(k));
            else,                  N(7).Value = sprintf('%.1f export', -u.Pgrid(k));
            end

            % status
            if day
                ck = app.Pack.day.clock0 + minutes(5*t/app.Pack.day.step);
                tm = char(string(ck, 'HH:mm'));
            else
                tm = sprintf('%+.0f ms', 1e3*(t - u.t_event));
                if t < u.T, tm = sprintf('%s (%dx slower)', tm, round(1/app.rate())); end
            end
            if app.Paused, tm = [tm ' (paused)']; end
            app.UI.time.Value = tm;
            [msg, c] = app.status(u, k, t, lim);
            app.UI.relay.Value = msg;  app.UI.lamp.Color = c;
            r = app.card(u, t);
            if ~isequal(app.UI.card.Value, {r}), app.UI.card.Value = {r}; end
            app.Frames = app.Frames + 1;
            drawnow limitrate
        end

        function [msg, c] = status(~, u, k, t, lim)
            ok = [0.39 0.83 0.07];  warn = [1 0.75 0];  bad = [1 0 0];    % uilamp green, amber, red
            tripped = u.trip(k) > 0.5;  oob = u.oob(k);
            if u.kind == "day" || t < u.t_event
                c = ok;  msg = 'Connected, armed';  return
            end
            switch u.kind
                case "dip"
                    if tripped,           c = bad;  msg = 'Tripped';
                    elseif t < u.t_clear, c = warn; msg = 'Fault, riding through';
                    elseif oob > 0,       c = warn; msg = sprintf('Out of band %.0f ms', oob);
                    else,                 c = ok;   msg = 'Fault cleared, no trip';
                    end
                case "shed"
                    if tripped,           c = bad;  msg = 'Tripped';
                    elseif oob > 0,       c = warn; msg = sprintf('Out of band %.0f ms', oob);
                    else,                 c = ok;   msg = 'Load off, no trip';
                    end
                case "island"
                    if tripped,           c = ok;   msg = sprintf('Tripped (%.0f ms)', 1e3*(u.t_trip - u.t_event));
                    elseif t - u.t_event > lim.t_island_max, c = bad; msg = 'Island still energised';
                    else,                 c = warn; msg = 'Grid lost, island energised';
                    end
            end
        end

        function s = card(~, u, t)
        % The measured result, once the outcome is on screen.
            v = u.v;  s = '';
            switch u.kind
                case "day"
                    s = 'Measured weather: Gullen Range NSW, 6 Oct 2026 (AEMO 5-min data).';
                case "dip"
                    if t >= u.t_clear + 0.15
                        if v.tripped
                            s = 'FAIL: tripped during the fault.';
                        else
                            s = sprintf(['%s: no trip. DC bus peak %.0f V (limit 800 V). Power back %.2f s after ' ...
                                'clearing (limit 1 s). Current peak %.0f A.'], tern(v.pass, 'PASS', 'FAIL'), ...
                                v.Vdc_peak, v.P_back_s, v.i_pk_A);
                        end
                    end
                case "shed"
                    if t >= u.t_event + 0.08
                        % total time out of band after the shed, as the deck quotes it
                        m  = (u.f < 47 | u.f > 52) & u.tS >= u.t_event;
                        to = 1e3*double(u.tS(2) - u.tS(1))*sum(m);
                        s = sprintf(['%s: %s. PLL out of band for %.0f ms in total (relay trips after 50 ms). ' ...
                            'DC bus peak %.0f V.'], tern(v.tripped, 'FAIL', 'PASS'), ...
                            tern(v.tripped, 'false trip', 'no false trip'), to, v.Vdc_peak);
                    end
                case "island"
                    if u.sfs && isfinite(u.t_trip) && t >= u.t_trip + 0.02
                        s = sprintf('PASS: island detected. Relay tripped %.1f ms after the grid opened (limit 2 s).', v.detect_ms);
                    elseif ~u.sfs && t >= u.t_event + 2.05
                        s = sprintf(['FAIL: island not detected. No trip after %.1f s; frequency stayed at ' ...
                            '%.1f-%.1f Hz.'], u.T - u.t_event, v.f_island);
                    end
            end
        end

        function h = clockH(app, t)
            h = hour(app.Pack.day.clock0) + minute(app.Pack.day.clock0)/60 + 5*double(t)/app.Pack.day.step/60;
        end
    end

    methods (Static, Access = private)
        function ax = mkAxes(parent, tag, ttl, yl)
            ax = uiaxes(parent);
            ax.Toolbar.Visible = 'off';  disableDefaultInteractivity(ax);
            ax.FontSize = 12;  ax.Box = 'on';  ax.XGrid = 'on';  ax.YGrid = 'on';
            ax.XLimMode = 'manual';  ax.YLimMode = 'manual';  ax.Tag = tag;
            title(ax, ttl);
            if yl ~= "", ylabel(ax, yl); end
            hold(ax, 'on');
        end

        function e = field(parent, row, label, fs)
        % A label and a read-only text field across the last two columns.
            LiveDemo.at(uilabel(parent, 'Text',label, 'FontSize',fs), row, 1);
            e = uieditfield(parent, 'text', 'Editable','off', 'FontSize',fs);
            LiveDemo.at(e, row, [2 3]);
        end

        function at(h, row, col)
            h.Layout.Row = row;  h.Layout.Column = col;
        end

        function o = oobRun(u, lim)
        % Running time (ms) the PLL frequency has been outside the relay band.
            m = u.f < lim.f_min | u.f > lim.f_max;  dS = 1e3*double(u.tS(2) - u.tS(1));
            o = zeros(size(m), 'single');
            for j = 2:numel(m), if m(j), o(j) = o(j-1) + dS; end, end
        end
    end
end

function v = tern(c, a, b), if c, v = a; else, v = b; end, end
