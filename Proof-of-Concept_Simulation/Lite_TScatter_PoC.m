% Lite_TScatter_PoC.m
%
% Matrix/vector-only proof-of-concept for Lite TScatter.
%
% This is intentionally NOT an 802.11n protocol simulation.  It uses the
% same familiar OFDM block size only to make the samples concrete:
%
%   64 useful OFDM time samples + 16 cyclic-prefix samples = 80 samples.
%
% Lite TScatter is modeled here as one simple tag phase per whole OFDM
% block.  This is the clean contrast with Full TScatter:
%
%   Lite: one backscatter phase b_m per 80-sample OFDM block.
%   Full: one backscatter phase v_n per useful time sample.
%
% The receiver knows the original WiFi samples and uses one predefined
% reference block to remove the common phase.  The remaining signs recover
% the Lite tag bits.

clear;
clc;
rng(11);

fprintf('\n');
fprintf('============================================================\n');
fprintf(' Matrix-only Lite TScatter proof-of-concept\n');
fprintf('============================================================\n');

%% 1. Dimensions: one OFDM block has 64 useful samples + 16 CP samples
N = 64;
Ncp = 16;
Nblock = N + Ncp;
nReference = 1;
nUnknown = 8;
nBlocks = nReference + nUnknown;

k = (0:N-1).';
n = 0:N-1;
W = exp(-1j*2*pi*(k*n)/N);
Winv = (1/N) * W';

% CP insertion and removal matrices.
I = eye(N);
Pcp = [I(end-Ncp+1:end,:); I];                 % 80 x 64
Rcp = [zeros(N,Ncp), eye(N)];                  % 64 x 80
cpIdentityError = norm(Rcp*Pcp-eye(N),'fro');

%% 2. Known WiFi OFDM blocks
% No WLAN protocol stack is used.  We only need deterministic OFDM-like
% complex waveforms that the receiver knows.
freqData = complex(sign(randn(N,nBlocks)),sign(randn(N,nBlocks)));
freqData(33,:) = 0;                            % DC-like null, for readability

usefulSamples = Winv*freqData;                 % 64 x nBlocks
txBlocks80 = Pcp*usefulSamples;                % 80 x nBlocks

%% 3. Lite tag phase: one +/-1 value per whole 80-sample block
trueBits = randi([0 1],nUnknown,1);
bTrue = ones(nBlocks,1);
bTrue(1) = 1;                                  % predefined reference block
bTrue(2:end) = 2*trueBits - 1;

% SISO scalar channels keep the Lite mechanism transparent.
hf = 0.82 * exp(1j*0.37);
hb = 1.18 * exp(-1j*0.61);
beta = pi/4;                                   % common phase, unknown to decoder

%% 4. Physical Lite chain over 80 samples
% For block m:
%   y_m = exp(j beta) * hb * b_m * hf * x80_m.
%
% The tag phase b_m multiplies the entire 80-sample OFDM block.
yRx80 = zeros(Nblock,nBlocks);
for blockIdx = 1:nBlocks
    yRx80(:,blockIdx) = exp(1j*beta) * hb * bTrue(blockIdx) * hf * txBlocks80(:,blockIdx);
end

%% 5. Channel compensation and reference-phase compensation
z80 = yRx80 / (hf*hb);
zDirectFormula = exp(1j*beta) * txBlocks80 .* reshape(bTrue,1,[]);
channelCompError = norm(z80-zDirectFormula,'fro')/norm(z80,'fro');

% Estimate each block's scalar phase by projecting onto the known WiFi block.
alpha = zeros(nBlocks,1);
for blockIdx = 1:nBlocks
    x80 = txBlocks80(:,blockIdx);
    alpha(blockIdx) = (x80' * z80(:,blockIdx)) / (x80' * x80);
end

% The first block is predefined b=+1, so alpha(1) estimates exp(j beta).
betaReference = alpha(1)/abs(alpha(1));
relativeTag = alpha ./ betaReference;
bHat = sign(real(relativeTag));
bHat(bHat==0) = 1;

bitHat = bHat(2:end) > 0;
bitErrors = sum(bitHat ~= trueBits);
referencePhaseError = abs(angle(betaReference)-beta);

%% 6. Trace for human inspection
timeView = [1:12 65:80].';
blockView = (1:nBlocks).';

fprintf('\n--- Lite dimensions ---\n');
fprintf('Useful samples per OFDM block                 : %d\n',N);
fprintf('CP samples per OFDM block                     : %d\n',Ncp);
fprintf('Total time samples per Lite block             : %d\n',Nblock);
fprintf('Reference blocks                              : %d\n',nReference);
fprintf('Unknown Lite tag bits                         : %d\n',nUnknown);

fprintf('\n--- Sanity checks ---\n');
fprintf('Rcp*Pcp identity error                        : %.3e\n',cpIdentityError);
fprintf('Channel compensation formula error            : %.3e\n',channelCompError);
fprintf('Reference common-phase error                  : %.3e rad\n',referencePhaseError);

fprintf('\n--- Selected vectors ---\n');
showComplexVector('1) First known 80-sample WiFi block with CP',txBlocks80(:,1),timeView);
showComplexVector('2) First received 80-sample Lite block',yRx80(:,1),timeView);
showComplexVector('3) First channel-compensated Lite block',z80(:,1),timeView);

fprintf('\nLite block tag phases: [block, true, decoded, real(relativeTag)]\n');
disp(table(blockView,bTrue,bHat,real(relativeTag), ...
    'VariableNames',{'block','truePhase','decodedPhase','metric'}));

fprintf('\n--- Decode result ---\n');
fprintf('Lite tag errors                               : %d/%d\n',bitErrors,nUnknown);
fprintf('Lite tag BER                                  : %.4f\n',bitErrors/nUnknown);

function showComplexVector(titleText,v,idx)
%SHOWCOMPLEXVECTOR Print selected entries of a complex vector.
    idx = idx(:);
    T = table(idx,real(v(idx)),imag(v(idx)),abs(v(idx)),angle(v(idx)), ...
        'VariableNames',{'index','real','imag','magnitude','phase_rad'});
    fprintf('\n%s\n',titleText);
    disp(T);
end
