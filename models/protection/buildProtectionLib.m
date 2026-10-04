function buildProtectionLib()
%BUILDPROTECTIONLIB Generate protectionLib.slx — the reusable relay block.
%   Creates a library holding AntiIslandingRelay, the over/under-frequency
%   relay with startup blocking and a persistence delay. This is the block
%   integration links to; SFS.slx links to the same one, so the rig and the
%   integrated model cannot drift apart.
%
%   Follows the convention in models/inverter: the .slx is GENERATED from
%   this script, so the source of truth is text that git can merge. Edit
%   here and re-run; do not edit the library by hand.
%
%       AntiIslandingRelay
%         in   f_hz   Hz   frequency estimate at the PCC
%         out  trip   -    1 once the relay has latched, 0 before
%
%         mask f_min, f_max   Hz   trip band
%              t_arm          s    relay blocked before this
%              t_pickup       s    out-of-band must persist this long
%              Ts             s    rate of the persistence timer
%
%   Defaults are numeric and self-contained, so the block works in a model
%   that has never heard of protectionParams. The rig passes pp.* values.
%
%   See also PROTECTIONPARAMS, PLL_STARTUP_PROBE, PLL_JUMP_PROBE

here = fileparts(mfilename('fullpath'));
lib  = 'protectionLib';
blk  = [lib '/AntiIslandingRelay'];

if bdIsLoaded(lib), close_system(lib, 0); end
new_system(lib, 'Library');
load_system(lib);

add_block('built-in/Subsystem', blk, 'Position', [100 100 260 180]);
delete_block_contents(blk);

% --- ports -----------------------------------------------------------
add_block('simulink/Sources/In1',  [blk '/f_hz'], 'Position',[30  200  60  214]);
add_block('simulink/Sinks/Out1',   [blk '/trip'], 'Position',[780 200 810 214]);

% --- out of band ------------------------------------------------------
add_block('simulink/Sources/Constant', [blk '/f_max'], ...
    'Position',[30 120 80 140], 'Value','f_max');
add_block('simulink/Sources/Constant', [blk '/f_min'], ...
    'Position',[30 270 80 290], 'Value','f_min');
add_block('simulink/Logic and Bit Operations/Relational Operator', ...
    [blk '/OverFreq'],  'Position',[130 135 160 165]);
add_block('simulink/Logic and Bit Operations/Relational Operator', ...
    [blk '/UnderFreq'], 'Position',[130 250 160 280]);
add_block('simulink/Logic and Bit Operations/Logical Operator', ...
    [blk '/OutOfBand'], 'Position',[210 195 240 225]);

% --- blocking: is the estimate valid yet? -----------------------------
add_block('simulink/Sources/Clock',    [blk '/Clk'],   'Position',[130 340 150 360]);
add_block('simulink/Sources/Constant', [blk '/t_arm'], ...
    'Position',[130 390 180 410], 'Value','t_arm');
add_block('simulink/Logic and Bit Operations/Relational Operator', ...
    [blk '/Armed'], 'Position',[230 345 260 375]);
add_block('simulink/Logic and Bit Operations/Logical Operator', ...
    [blk '/Confirm'], 'Position',[310 255 340 285]);

% --- persistence: has it held long enough? ----------------------------
add_block('simulink/Logic and Bit Operations/Logical Operator', ...
    [blk '/NotCond'], 'Position',[390 255 420 285]);
add_block('simulink/Sources/Constant', [blk '/One'], ...
    'Position',[390 170 420 190], 'Value','1');
add_block('simulink/Discrete/Discrete-Time Integrator', ...
    [blk '/PickupTimer'], 'Position',[470 160 520 210]);
add_block('simulink/Sources/Constant', [blk '/t_pickup'], ...
    'Position',[470 250 530 270], 'Value','t_pickup');
add_block('simulink/Logic and Bit Operations/Relational Operator', ...
    [blk '/PickedUp'], 'Position',[580 175 610 205]);

% --- latch ------------------------------------------------------------
add_block('simulink/Logic and Bit Operations/Logical Operator', ...
    [blk '/Latch'],    'Position',[670 185 700 215]);
add_block('simulink/Discrete/Memory', [blk '/HoldTrip'], ...
    'Position',[670 270 700 300]);

% --- parameters -------------------------------------------------------
set_param([blk '/OutOfBand'], 'Operator','OR',  'Inputs','2');
set_param([blk '/Confirm'],   'Operator','AND', 'Inputs','2');
set_param([blk '/NotCond'],   'Operator','NOT', 'Inputs','1');
set_param([blk '/Latch'],     'Operator','OR',  'Inputs','2');
set_param([blk '/PickupTimer'], ...
    'IntegratorMethod','Integration: Forward Euler', ...
    'gainval','1', 'InitialCondition','0', ...
    'SampleTime','Ts', 'ExternalReset','level');

% The '>' character has silently failed to stick through model tooling
% before, so build the operators from character codes and read them back.
ge = char([62 61]);   % '>='
le = char([60 61]);   % '<='
set_param([blk '/OverFreq'],  'Operator', ge);
set_param([blk '/UnderFreq'], 'Operator', le);
set_param([blk '/Armed'],     'Operator', ge);
set_param([blk '/PickedUp'],  'Operator', ge);

% --- wiring -----------------------------------------------------------
w = @(a,b) add_line(blk, a, b, 'autorouting','on');
w('f_hz/1','OverFreq/1');     w('f_max/1','OverFreq/2');
w('f_hz/1','UnderFreq/1');    w('f_min/1','UnderFreq/2');
w('OverFreq/1','OutOfBand/1');w('UnderFreq/1','OutOfBand/2');
w('Clk/1','Armed/1');         w('t_arm/1','Armed/2');
w('OutOfBand/1','Confirm/1'); w('Armed/1','Confirm/2');
w('Confirm/1','NotCond/1');
w('One/1','PickupTimer/1');   w('NotCond/1','PickupTimer/2');
w('PickupTimer/1','PickedUp/1'); w('t_pickup/1','PickedUp/2');
w('PickedUp/1','Latch/1');    w('HoldTrip/1','Latch/2');
w('Latch/1','HoldTrip/1');    w('Latch/1','trip/1');

% --- mask -------------------------------------------------------------
m = Simulink.Mask.create(blk);
m.Display = sprintf(['disp(''Anti-islanding\\nrelay'')\n']);
m.Description = [ ...
  'Over/under-frequency relay with startup blocking and a persistence ' ...
  'delay.' newline newline ...
  'Latches trip when the frequency estimate has been outside ' ...
  '[f_min, f_max] continuously for t_pickup, and only after t_arm.' ...
  newline newline ...
  'BLOCKING (t_arm): a PLL frequency estimate is meaningless until the ' ...
  'loop has acquired lock. Aqib''s SRF-PLL leaves the 47-52 Hz band for ' ...
  'up to 170 ms at startup, worst case at a 270 deg initial phase. ' ...
  'Without blocking the relay latches at t = 0.' newline newline ...
  'PERSISTENCE (t_pickup): a 30 deg phase jump - the SC4 stimulus, which ' ...
  'the PLL is specified to ride through - drives the estimate to 60 Hz ' ...
  'for 12.4 ms. Without persistence the relay trips on a grid event the ' ...
  'plant must survive.' newline newline ...
  'Both figures are measured: see pll_startup_probe and pll_jump_probe.' ...
  newline newline ...
  'The latch is permanent. AS/NZS 4777.2 requires reconnection after 60 s ' ...
  'within limits; that is not implemented here.'];

addP(m, 'f_min',    'Under-frequency trip (Hz)',      '47');
addP(m, 'f_max',    'Over-frequency trip (Hz)',       '52');
addP(m, 't_arm',    'Relay blocked until (s)',        '0.5');
addP(m, 't_pickup', 'Out-of-band must persist (s)',   '0.1');
addP(m, 'Ts',       'Persistence timer rate (s)',     '1e-4');

% --- verify every parameter stuck -------------------------------------
chk = {'OverFreq','Operator',ge; 'UnderFreq','Operator',le; ...
       'Armed','Operator',ge;    'PickedUp','Operator',ge; ...
       'OutOfBand','Operator','OR'; 'Confirm','Operator','AND'; ...
       'NotCond','Operator','NOT'; 'Latch','Operator','OR'; ...
       'PickupTimer','ExternalReset','level'};
fprintf('\n--- library block verification ---\n');
ok = true;
for k = 1:size(chk,1)
    got  = get_param([blk '/' chk{k,1}], chk{k,2});
    good = strcmp(got, chk{k,3});
    ok   = ok && good;
    fprintf('  %-12s %-14s = %-28s %s\n', chk{k,1}, chk{k,2}, got, string(good));
end
assert(ok, 'A parameter did not stick - library not saved.');

set_param(lib,'Lock','off');
save_system(lib, fullfile(here,[lib '.slx']));
fprintf('\nwritten: %s\n', fullfile(here,[lib '.slx']));
close_system(lib, 0);
end

% ---------------------------------------------------------------------
function addP(m, name, prompt, value)
m.addParameter('Type','edit', 'Name',name, 'Prompt',prompt, 'Value',value);
end

% ---------------------------------------------------------------------
function delete_block_contents(sys)
b = find_system(sys, 'SearchDepth',1, 'LookUnderMasks','all', 'Type','Block');
for k = 1:numel(b)
    if ~strcmp(b{k}, sys), delete_block(b{k}); end
end
end
