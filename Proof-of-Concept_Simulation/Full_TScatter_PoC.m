% Full_TScatter_PoC.m
%
% Matrix-only proof-of-concept for the TScatter Full Decoder.
%
% This script is intentionally written like the paper derivation rather than
% like a signal-processing program.  It does NOT call the built-in FFT or
% inverse-FFT functions.
% Instead it explicitly builds the 64x64 DFT matrix W and inverse matrix W^{-1}.
%
% Count discipline in this PoC:
%
%   N = 64 useful OFDM time samples.
%   The tag multiplies EVERY useful time sample by one phase value.
%   Therefore v is 64x1:
%       v(1:48)   = unknown backscatter bits/phases in {+1,-1}
%       v(49:64)  = known/predefined phases, here fixed to +1
%
% We do not model CP, CFO, SFO, timing offset, multipath, or noise here.
% If desired later:
%   - CP can be represented by an 80x64 CP insertion matrix and a 64x80
%     receiver crop/removal matrix.
%   - CFO can be represented by a time-domain diagonal matrix
%     C_cfo = diag(exp(j*2*pi*epsilon*n/N)).
%
% Main matrix chain:
%
%   x        : 64x1 original WiFi frequency-domain OFDM symbol
%   Hf       : 64x64 diagonal forward channel, Tx -> tag
%   Hb       : 64x64 diagonal backward channel, tag -> Rx
%   W        : 64x64 DFT matrix
%   Winv     : 64x64 IDFT matrix
%   D(v)     : diag(v), 64x64 sample-level tag modulation
%
% Physical receive model:
%
%   y = exp(j*beta) * Hb * W * D(v) * Winv * Hf * x
%
% Ordinary WiFi channel compensation by the cascaded channel Hf*Hb:
%
%   z = (Hf*Hb)^{-1} y
%     = exp(j*beta) * Hf^{-1} * W * D(v) * Winv * Hf * x
%
% Decoder matrix:
%
%   A(:,i) = Hf^{-1} * W * D(e_i) * Winv * Hf * x
%
% where e_i is the ith basis vector.  Since D(v)=sum_i v_i D(e_i),
%
%   z = exp(j*beta) * A * v.
%
% Pilot compensation, matching the idea of paper Eq. 13/15:
%
%   Psi  = angle( sum_{pilot k} z_k * conj(x_k) )
%   zbar = exp(-j*Psi) * z
%
% For the correct v, this leaves
%
%   zbar = c(v) * A * v,
%   c(v) = conj(Gamma(v))/|Gamma(v)|,
%   Gamma(v) = sum_{pilot k} (A_k v) * conj(x_k).
%
% Finally, the decoder solves the unknown 48 entries of v while treating the
% last 16 predefined entries as known compensation/reference samples.

clear;
clc;
rng(7);

fprintf('\n');
fprintf('============================================================\n');
fprintf(' Matrix-only Full TScatter proof-of-concept\n');
fprintf('============================================================\n');

%% 1. Paper/WiFi dimensions and index sets
N = 64;
nUnknown = 48;
nKnown = N - nUnknown;
QAM = 64;

pilot = [12 26 40 54].';                      % paper pilots {11,25,39,53} + 1
pilotValue = [1 1 1 -1].';
guard = [1:6 60:64].';                         % paper guards {0..5,59..63} + 1
dc = 33;                                       % paper DC 32 + 1
data = setdiff((7:59).',[pilot;dc]);           % 48 data subcarriers

freqView = [7:18 26 33 40 54].';
timeView = (1:16).';
tagView = [1:12 37:44 61:64].';

%% 2. Explicit matrix form of DFT and IDFT
% W follows MATLAB's DFT sign convention, but we use it only as a matrix.
% No built-in FFT or inverse-FFT function is called in this script.
k = (0:N-1).';
n = 0:N-1;
W = exp(-1j*2*pi*(k*n)/N);
Winv = (1/N) * W';

matrixIdentityError = norm(W*Winv-eye(N),'fro');

%% 3. One original WiFi OFDM symbol x
x = zeros(N,1);
x(data) = qammod(randi([0 QAM-1],numel(data),1),QAM);
x(pilot) = pilotValue;

%% 4. Frequency-selective channels as diagonal matrices
% Every subcarrier has a different complex value.  This is the channel model
% the old PoC tried to compensate: Hf and Hb are not scalar channels.
hf = (0.85+0.25*cos(2*pi*k/N+0.2)) .* ...
     exp(1j*(0.60*sin(2*pi*k/N)+0.018*k));
hb = (0.90+0.20*sin(4*pi*k/N+0.4)) .* ...
     exp(1j*(0.45*cos(2*pi*k/N)-0.014*k));

Hf = diag(hf);
Hb = diag(hb);
Hcascade = Hf*Hb;

%% 5. Sample-level tag phase vector: 64 samples = 64 tag phases
unknown = false(N,1);
unknown(1:nUnknown) = true;
known = ~unknown;

trueBit = randi([0 1],nUnknown,1);
vTrue = ones(N,1);
vTrue(unknown) = 2*trueBit - 1;                % theta in {0,pi}: exp(j theta)=+1/-1
vTrue(known) = 1;                              % 24 predefined known samples

DvTrue = diag(vTrue);
beta = pi/5;                                   % common phase; not given to decoder

%% 6. Forward physical chain, written only as matrix multiplication
% Correspondence to paper's sample-level modulation:
%   s_tag = Winv * Hf * x
%   r_tag = D(v) * s_tag
%   y     = exp(j beta) * Hb * W * r_tag
xAtTag = Hf*x;
sAtTag = Winv*xAtTag;
sAfterTag = DvTrue*sAtTag;
yBeforeHb = W*sAfterTag;
yRx = exp(1j*beta) * Hb*yBeforeHb;

%% 7. Channel compensation
% Ordinary receiver equalization removes the cascaded channel Hf*Hb:
%   z = (Hf*Hb)^{-1} y.
% Hb disappears.  Hf remains around D(v), so the decoder must still model Hf:
%   z = exp(j beta) * Hf^{-1} * W * D(v) * Winv * Hf * x.
z = Hcascade \ yRx;
zDirectFormula = exp(1j*beta) * (Hf \ (W*DvTrue*Winv*Hf*x));
channelCompError = norm(z-zDirectFormula)/norm(z);

%% 8. Decoder-side relative Hf compensation and matrix A
% In the Sylvester-like calibration stage, Hf is recovered up to one
% scalar.  That is enough here: the scalar cancels inside A.
reference = data(1);
HfEst = Hf / Hf(reference,reference);

sEst = Winv*HfEst*x;
A = zeros(N,N);
for sampleIdx = 1:N
    e = zeros(N,1);
    e(sampleIdx) = 1;
    De = diag(e);
    A(:,sampleIdx) = HfEst \ (W*De*sEst);
end

zFromA = exp(1j*beta) * A*vTrue;
modelError = norm(z-zFromA)/norm(z);

%% 9. Pilot phase compensation and Gamma(v)
% Eq. 13 / Eq. 15 style pilot correction.
Psi = angle(sum(z(pilot).*conj(pilotValue)));
zbar = exp(-1j*Psi) * z;

% Eq. 14 / Eq. 16 style residual phase as a function of candidate v.
gammaRow = sum(A(pilot,:).*conj(pilotValue),1); % 1x64
GammaTrue = gammaRow*vTrue;
cTrue = conj(GammaTrue)/abs(GammaTrue);
pilotCompError = norm(zbar-cTrue*(A*vTrue))/norm(zbar);

%% 10. Decode the unknown tag phases using known 16 samples
% Use the 48 data subcarriers as equations, matching the paper's Full Decoder
% spirit after pilot correction.  The known tag samples are moved to the
% right-hand side as a compensation/reference term.
Adata = A(data,:);
ydata = zbar(data);

Aunknown = Adata(:,unknown);
Aknown = Adata(:,known);
vKnown = vTrue(known);                          % in practice predefined, not secret
knownPart = Aknown*vKnown;

C = [real(Aunknown); imag(Aunknown)];

bestCost = inf;
vHat = ones(N,1);
bestC = 1;
phaseGrid = 2*pi*(0:127)/128;

for phase = phaseGrid
    % Hold residual phase c fixed, solve a linear LS problem for unknown v.
    c = exp(1j*phase);
    rhs = ydata.*conj(c) - knownPart;
    d = [real(rhs); imag(rhs)];

    vFree = C\d;
    vHardUnknown = sign(vFree);
    vHardUnknown(vHardUnknown==0) = 1;

    candidate = ones(N,1);
    candidate(known) = vKnown;
    candidate(unknown) = vHardUnknown;

    Gamma = gammaRow*candidate;
    if abs(Gamma) < eps
        continue;
    end
    cCandidate = conj(Gamma)/abs(Gamma);
    cost = norm(ydata-cCandidate*(Adata*candidate))^2;

    if cost < bestCost
        bestCost = cost;
        vHat = candidate;
        bestC = cCandidate;
    end
end

% A tiny hard-decision coordinate refinement over the physical alphabet.
[vHat,bestCost,bestC] = refineHard(vHat,unknown,Adata,gammaRow,ydata,bestCost,bestC);

estimatedBit = vHat(unknown) > 0;
bitErrors = sum(estimatedBit ~= trueBit);

%% 11. Trace for human inspection
trace = struct();
trace.W = W;
trace.Winv = Winv;
trace.x = x;
trace.hf = hf;
trace.hb = hb;
trace.Hf = Hf;
trace.Hb = Hb;
trace.vTrue = vTrue;
trace.DvTrue = DvTrue;
trace.xAtTag = xAtTag;
trace.sAtTag = sAtTag;
trace.sAfterTag = sAfterTag;
trace.yBeforeHb = yBeforeHb;
trace.yRx = yRx;
trace.zAfterChannelCompensation = z;
trace.A = A;
trace.zFromA = zFromA;
trace.Psi = Psi;
trace.zbarAfterPilotCompensation = zbar;
trace.gammaRow = gammaRow;
trace.vHat = vHat;

fprintf('\n--- Matrix definitions and dimensions ---\n');
fprintf('N useful time samples                         : %d\n',N);
fprintf('Tag phases v                                  : %d total = %d unknown + %d known\n', ...
    N,nUnknown,nKnown);
fprintf('W size, Winv size                             : %dx%d, %dx%d\n', ...
    size(W,1),size(W,2),size(Winv,1),size(Winv,2));
fprintf('Hf/Hb/Hcascade size                           : %dx%d\n',N,N);
fprintf('A size                                        : %dx%d\n',size(A,1),size(A,2));
fprintf('Data equations used for decoding              : %d complex equations\n',numel(data));
fprintf('Unknowns decoded                              : %d real +/-1 phases\n',nUnknown);

fprintf('\n--- Sanity checks ---\n');
fprintf('W*Winv identity error                         : %.3e\n',matrixIdentityError);
fprintf('Channel compensation formula error            : %.3e\n',channelCompError);
fprintf('Matrix model error, z vs exp(j beta)*A*v      : %.3e\n',modelError);
fprintf('Pilot compensation model error, zbar vs c*A*v : %.3e\n',pilotCompError);
fprintf('Common beta used in transmitter               : %.3f rad\n',beta);
fprintf('Pilot-estimated Psi                           : %.3f rad\n',Psi);
fprintf('Decoder residual phase c angle                : %.3f rad\n',angle(bestC));

fprintf('\n--- Selected vectors ---\n');
showComplexVector('1) x: original WiFi frequency-domain symbol',x,freqView);
showComplexVector('2) hf: forward channel diagonal values',hf,freqView);
showComplexVector('3) hb: backward channel diagonal values',hb,freqView);
showComplexVector('4) sAtTag = Winv * Hf * x',sAtTag,timeView);
showRealVector('5) vTrue: 64 sample-level tag phases, first 48 unknown, last 16 known',vTrue,tagView);
showComplexVector('6) sAfterTag = D(vTrue) * sAtTag',sAfterTag,timeView);
showComplexVector('7) yRx = exp(j beta) * Hb * W * D(v) * Winv * Hf * x',yRx,freqView);
showComplexVector('8) z = (Hf*Hb)^{-1} * yRx',z,freqView);
showComplexVector('9) A*vTrue, before common phase beta',A*vTrue,freqView);
showComplexVector('10) zbar = exp(-j Psi) * z',zbar,freqView);

fprintf('\n--- Decode result ---\n');
fprintf('Tag errors                                    : %d/%d\n',bitErrors,nUnknown);
fprintf('Tag BER                                       : %.4f\n',bitErrors/nUnknown);
disp('First 16 unknown tag phases: [true, decoded]');
disp([vTrue(find(unknown,16,'first')),vHat(find(unknown,16,'first'))]);

function showComplexVector(titleText,v,idx)
%SHOWCOMPLEXVECTOR Print selected entries of a complex vector.
    idx = idx(:);
    T = table(idx,real(v(idx)),imag(v(idx)),abs(v(idx)),angle(v(idx)), ...
        'VariableNames',{'index','real','imag','magnitude','phase_rad'});
    fprintf('\n%s\n',titleText);
    disp(T);
end

function showRealVector(titleText,v,idx)
%SHOWREALVECTOR Print selected entries of a real vector.
    idx = idx(:);
    T = table(idx,v(idx),'VariableNames',{'index','value'});
    fprintf('\n%s\n',titleText);
    disp(T);
end

function [vBest,costBest,cBest] = refineHard(vStart,unknownMask,A,gammaRow,y,costStart,cStart)
%REFINEHARD Coordinate refinement over v_i in {+1,-1}.
    vBest = vStart;
    costBest = costStart;
    cBest = cStart;
    slots = find(unknownMask);
    for pass = 1:3
        improved = false;
        for ii = 1:numel(slots)
            trial = vBest;
            trial(slots(ii)) = -trial(slots(ii));
            Gamma = gammaRow*trial;
            if abs(Gamma) < eps
                continue;
            end
            cTrial = conj(Gamma)/abs(Gamma);
            costTrial = norm(y-cTrial*(A*trial))^2;
            if costTrial < costBest
                vBest = trial;
                costBest = costTrial;
                cBest = cTrial;
                improved = true;
            end
        end
        if ~improved
            break;
        end
    end
end
