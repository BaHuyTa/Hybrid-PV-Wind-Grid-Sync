function out = recordDemo(out, opts)
%RECORDDEMO  Backup video of LiveDemo: one loop of the day, then every event.
%
%   recordDemo()                       demo/LiveDemo_backup.mp4, 1920x1080, 20 fps
%   recordDemo("x.mp4", Fps=25)
%
% For a laptop without MATLAB, or if the app misbehaves at the table. The app is
% stepped frame by frame (no timer), so the video runs at the app's true speed
% however slow the capture is. VideoWriter MPEG-4 where it exists (Windows, macOS);
% on Linux, PNG frames + ffmpeg.
%
% The tour: the day at 150, 250 and 50 kW (one 60 s loop), then a grid fault and
% a load shed at 250 kW, and grid lost with SFS on and off.

arguments
    out (1,1) string = ""
    opts.Fps (1,1) double = 20
    opts.Size (1,2) double = [1920 1080]
    opts.Pack (1,1) string = ""
end
here = fileparts(mfilename('fullpath'));
if out == "", out = fullfile(here, "LiveDemo_backup.mp4"); end
app = LiveDemo(Pack=opts.Pack, Window=[0 0 opts.Size], Start=false);
app.HoldEnd = 6;
done = onCleanup(@() delete(app));
drawnow;  pause(1);

useVW = any(strcmp({VideoWriter.getProfiles.Name}, 'MPEG-4'));
fdir  = tempname;  mkdir(fdir);
if useVW, vw = VideoWriter(out, 'MPEG-4'); vw.FrameRate = opts.Fps; vw.Quality = 90; open(vw); end
nf = 0;  t0 = tic;  dt = 1/opts.Fps;

    function shoot(seconds)
        for j = 1:round(seconds*opts.Fps)
            app.advance(dt);  app.frame(app.t);
            png = fullfile(fdir, sprintf('%05d.png', nf));
            exportapp(app.Fig, png);  nf = nf + 1;
            if useVW, writeVideo(vw, imread(png)); delete(png); end
        end
    end
    function event(kind)
        app.playEvent(kind);
        while app.Mode == "event", shoot(1); end
    end

app.setLoad(150);  shoot(24);
app.setLoad(250);  shoot(18);
app.setLoad(50);   shoot(18);
app.setLoad(250);  shoot(2);
event("dip");
event("shed");
app.setSfs(true);  event("island");
app.setSfs(false); event("island");
app.setSfs(true);  app.setLoad(150);  shoot(4);

if useVW
    close(vw);
else
    cmd = sprintf(['ffmpeg -y -loglevel error -framerate %g -i "%s" -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" ' ...
        '-c:v libx264 -pix_fmt yuv420p -crf 20 -movflags +faststart "%s"'], opts.Fps, fullfile(fdir, '%05d.png'), out);
    % MATLAB's LD_LIBRARY_PATH would hand ffmpeg MATLAB's own libstdc++, which is too old
    if isunix && ~ismac, cmd = ['env -u LD_LIBRARY_PATH ' cmd]; end
    [st, msg] = system(cmd);
    if st ~= 0, error('recordDemo:ffmpeg', 'ffmpeg failed (frames kept in %s): %s', fdir, msg); end
    rmdir(fdir, 's');
end
fprintf('%s: %d frames (%.0f s of video) in %.1f min\n', out, nf, nf/opts.Fps, toc(t0)/60);
end
