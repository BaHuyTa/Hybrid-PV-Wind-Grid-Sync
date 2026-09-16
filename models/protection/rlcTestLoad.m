function [R,L,C] = rlcTestLoad(dP,dQ,pp)
%RLCTESTLOAD Parallel RLC island test load for a given power mismatch.
%   [R,L,C] = RLCTESTLOAD(dP,dQ,pp) returns the parallel R-L-C branch values
%   for an islanding test load that mismatches the inverter output by dP in
%   real power and dQ in reactive power, both normalised to pp.P_inv, while
%   holding the quality factor at pp.Qf.
%
%   dP = dQ = 0 returns the matched, f_n-resonant load — the worst case for
%   passive anti-islanding detection, and the values cached in
%   protectionParams as pp.R_load, pp.L_load, pp.C_load.
%
%   The reactive elements follow from two constraints at f_n, where
%   B_C = 2*pi*f_n*C and B_L = 1/(2*pi*f_n*L):
%
%       B_L - B_C = dQ*P_inv/V^2      (net reactive mismatch)
%       B_C*B_L   = (Qf/R)^2          (quality factor, Qf = R*sqrt(C/L))
%
%   Example:
%       pp = protectionParams();
%       [R,L,C] = rlcTestLoad(0,0,pp);      % matched point
%       [R,L,C] = rlcTestLoad(0.1,-0.05,pp); % 10% over on P, 5% under on Q
%
%   See also PROTECTIONPARAMS

arguments
    dP (1,1) double
    dQ (1,1) double
    pp (1,1) struct
end

% Real power sets R alone.
P_load = pp.P_inv*(1 + dP);
R = pp.V_ph^2/P_load;

% Reactive: solve B_C^2 + dB*B_C - (Qf/R)^2 = 0 for the positive root.
dB   = dQ*pp.P_inv/pp.V_ph^2;
B_C  = (-dB + sqrt(dB^2 + 4*(pp.Qf/R)^2))/2;
B_L  = B_C + dB;

C = B_C/pp.w_n;
L = 1/(pp.w_n*B_L);
end
