% Full_TScatter_80211n_SISO.m
%
% Packet-level 802.11n SISO simulation of Full TScatter.
%
% This script is intentionally different from the math-only PoC:
%
%   * MATLAB WLAN Toolbox generates a real 802.11n HT packet.
%   * Two reproducible TGn SISO channels model Tx->tag and tag->Rx.
%   * A controllable carrier-frequency offset is added before the receiver.
%   * The receiver performs packet detection, coarse CFO correction,
%     timing synchronization, fine CFO correction, HT-LTF channel estimation,
%     and HT-Data recovery.
%   * Full TScatter is applied only to one HT-Data OFDM symbol as
%     sample-level +/-1 phase modulation over the 64 useful samples.
%   * A calibration pass through the same channel realization supplies the
%     frequency-selective H_f and H_f H_b compensation needed by the Full
%     decoder.
%
% The receiver chain follows the structure of the official MathWorks
% 802.11n TGn packet-error-rate example, but the TScatter tag modulation and
% tag-bit decoder are implemented here.

clear;
clc;
rng(21);

fprintf('\n');
fprintf('============================================================\n');
fprintf(' Full TScatter on packet-level 802.11n SISO / TGn channel\n');
fprintf('============================================================\n');

%% 1. 802.11n HT SISO configuration
cfgHT = wlanHTConfig;
cfgHT.ChannelBandwidth = 'CBW20';
cfgHT.NumTransmitAntennas = 1;
cfgHT.NumSpaceTimeStreams = 1;
cfgHT.MCS = 7;                         % 1 stream, 64-QAM, rate 5/6
cfgHT.ChannelCoding = 'BCC';
cfgHT.GuardInterval = 'Long';
cfgHT.PSDULength = 256;

fs = wlanSampleRate(cfgHT);
ofdmInfo = wlanHTOFDMInfo('HT-Data',cfgHT);
ind = wlanFieldIndices(cfgHT);

N = ofdmInfo.FFTLength;
Ncp = ofdmInfo.CPLength;
Nblock = N + Ncp;
nHTDataSamples = ind.HTData(2) - ind.HTData(1) + 1;
nHTDataSymbols = nHTDataSamples / Nblock;

activeRows = ofdmInfo.ActiveFFTIndices(:);
dataRows = activeRows(ofdmInfo.DataIndices(:));
pilotRows = activeRows(ofdmInfo.PilotIndices(:));

tagSymbol = 1;                         % One HT-Data OFDM symbol carries Full tag bits.
nUnknown = 48;                         % Paper-level Full TScatter target in this PoC.
nKnown = N - nUnknown;
unknown = false(N,1);
unknown(1:nUnknown) = true;
known = ~unknown;

W = shiftedDFTMatrix(N);
Winv = (1/N) * W';

%% 2. Generate one real 802.11n packet
txPSDU = randi([0 1],cfgHT.PSDULength*8,1);

% Disable windowing so each HT-Data OFDM block is exactly
% 16 CP samples + 64 useful samples. This keeps the tag operation visible.
tx = wlanWaveformGenerator(txPSDU,cfgHT,'WindowTransitionTime',0);
tx = [tx; zeros(15,cfgHT.NumTransmitAntennas)];

txHTData = tx(ind.HTData(1):ind.HTData(2),:);
txFreq = ofdmBlocksToFreq(txHTData,N,Ncp,W);
x = txFreq(:,tagSymbol);
pilotValue = x(pilotRows);

%% 3. Reproducible Tx->tag and tag->Rx TGn channels
tgnBefore = makeTGnChannel(cfgHT,fs,101,1,1,3);
tgnAfter = makeTGnChannel(cfgHT,fs,202,1,1,3);

reset(tgnBefore);
rxBeforeTag = tgnBefore(tx);

% The tag needs to know where the HT-Data field is in its received stream.
% We use the same packet/timing estimator as the receiver for this
% simulation. The tag does not decode the WiFi payload.
[tagPktOffset,tagTiming] = packetOffsetForFieldAccess(rxBeforeTag,cfgHT);
if tagTiming.detectionError
    error('Full_TScatter:TagTimingFailed','The tag could not locate HT-Data.');
end

%% 4. Full TScatter sample-level modulation on one 64-sample useful block
trueBits = randi([0 1],nUnknown,1);
vTrue = ones(N,1);
vTrue(unknown) = 2*trueBits - 1;
vTrue(known) = 1;                      % Known/predefined samples.

rxTaggedAtTag = rxBeforeTag;
tagBlockRows = double(tagPktOffset) + double(ind.HTData(1)) + (tagSymbol-1)*Nblock ...
    + (0:Nblock-1);
tagInputBlock = rxTaggedAtTag(tagBlockRows,:);
tagInputUseful = tagInputBlock(Ncp+1:end,:);
taggedUseful = vTrue .* tagInputUseful;
taggedBlock = [taggedUseful(end-Ncp+1:end,:); taggedUseful];
rxTaggedAtTag(tagBlockRows,:) = taggedBlock;

%% 5. Pass both calibration and tagged packets through the same tag->Rx channel
% Resetting a TGn channel with a fixed seed gives the same channel
% realization. The untagged packet is the calibration packet used to
% estimate H_f H_b. The tagged packet is the actual Full TScatter packet.
reset(tgnAfter);
rxNoTag = tgnAfter(rxBeforeTag);

reset(tgnAfter);
rxTagged = tgnAfter(rxTaggedAtTag);

% Add a receiver-side carrier-frequency offset. The receiver below must
% estimate and correct it before extracting HT-Data.
cfoHz = 2500;
rxNoTag = frequencyOffset(rxNoTag,fs,cfoHz);
rxTagged = frequencyOffset(rxTagged,fs,cfoHz);

snrDb = 80;
packetSNR = snrDb - 10*log10(ofdmInfo.FFTLength/ofdmInfo.NumTones);
rxTaggedNoisy = awgn(rxTagged,packetSNR,'measured');

%% 6. 802.11n receiver processing
cal = receiveHTPacket(rxNoTag,cfgHT);
rx = receiveHTPacket(rxTaggedNoisy,cfgHT);
if cal.detectionError
    error('Full_TScatter:CalibrationReceiverFailed','Calibration packet receiver failed.');
end
if rx.detectionError
    error('Full_TScatter:TaggedReceiverFailed','Tagged packet receiver failed.');
end

psduBitErrors = biterr(txPSDU,rx.rxPSDU);

%% 7. Frequency-selective channel compensation for the Full decoder
% Estimate H_f at the tag input from the Tx->tag calibration.
tagInputHTData = rxBeforeTag(double(tagPktOffset) + double(ind.HTData(1):ind.HTData(2)),:);
tagInputFreq = ofdmBlocksToFreq(tagInputHTData,N,Ncp,W);

hf = ones(N,1);
hf(activeRows) = tagInputFreq(activeRows,tagSymbol) ./ txFreq(activeRows,tagSymbol);

% Estimate H_f H_b from the untagged calibration packet at the receiver.
calFreq = ofdmBlocksToFreq(cal.htdata,N,Ncp,W);
hcascade = ones(N,1);
hcascade(activeRows) = calFreq(activeRows,tagSymbol) ./ txFreq(activeRows,tagSymbol);

% Compensate the tagged packet with H_f H_b.
rxTaggedFreq = ofdmBlocksToFreq(rx.htdata,N,Ncp,W);
y = rxTaggedFreq(:,tagSymbol);
z = zeros(N,1);
z(activeRows) = y(activeRows) ./ hcascade(activeRows);

% Sanity check: the calibration packet should become the original WiFi
% symbol after H_f H_b compensation.
zCal = zeros(N,1);
zCal(activeRows) = calFreq(activeRows,tagSymbol) ./ hcascade(activeRows);
calibrationCompError = norm(zCal(activeRows)-x(activeRows)) / norm(x(activeRows));

%% 8. Build the Full decoder matrix A using relative H_f
% Absolute channel scale is unnecessary. We normalize H_f by one active
% reference carrier, exactly like the math PoC.
reference = dataRows(1);
hfRel = hf / hf(reference);

sEst = Winv * (hfRel .* x);
A = zeros(N,N);
for sampleIdx = 1:N
    e = zeros(N,1);
    e(sampleIdx) = 1;
    A(:,sampleIdx) = (W * diag(e) * sEst) ./ hfRel;
end

modelRows = activeRows;
modelFit = bestComplexScale(A(modelRows,:)*vTrue,z(modelRows));
modelError = norm(z(modelRows)-modelFit*(A(modelRows,:)*vTrue)) / norm(z(modelRows));

%% 9. Pilot/Gamma compensation and hard Full-tag decoding
Psi = angle(sum(z(pilotRows).*conj(pilotValue)));
zbar = exp(-1j*Psi) * z;

gammaRow = sum(A(pilotRows,:).*conj(pilotValue),1);
GammaTrue = gammaRow*vTrue;
cTrue = conj(GammaTrue) / abs(GammaTrue);
pilotCompError = norm(zbar(dataRows)-cTrue*(A(dataRows,:)*vTrue)) / norm(zbar(dataRows));

Adata = A(dataRows,:);
ydata = zbar(dataRows);
Aunknown = Adata(:,unknown);
Aknown = Adata(:,known);
knownPart = Aknown*vTrue(known);
C = [real(Aunknown); imag(Aunknown)];

bestCost = inf;
vHat = ones(N,1);
bestC = 1;
for phase = 2*pi*(0:255)/256
    c = exp(1j*phase);
    rhs = ydata.*conj(c) - knownPart;
    vFree = C \ [real(rhs); imag(rhs)];
    vHard = sign(vFree);
    vHard(vHard==0) = 1;

    candidate = ones(N,1);
    candidate(known) = vTrue(known);
    candidate(unknown) = vHard;

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

[vHat,bestCost,bestC] = refineHard(vHat,unknown,Adata,gammaRow,ydata,bestCost,bestC);

bitHat = vHat(unknown) > 0;
tagBitErrors = sum(bitHat ~= trueBits);

%% 10. Results
fprintf('\n--- 802.11n SISO configuration ---\n');
fprintf('ChannelBandwidth                              : %s\n',cfgHT.ChannelBandwidth);
fprintf('NumTransmitAntennas                           : %d\n',cfgHT.NumTransmitAntennas);
fprintf('NumReceiveAntennas                            : %d\n',1);
fprintf('NumSpaceTimeStreams                           : %d\n',cfgHT.NumSpaceTimeStreams);
fprintf('MCS / PSDULength                              : %d / %d bytes\n',cfgHT.MCS,cfgHT.PSDULength);
fprintf('HT-Data OFDM symbols                          : %d\n',nHTDataSymbols);
fprintf('Useful / CP / block samples                   : %d / %d / %d\n',N,Ncp,Nblock);
fprintf('Full tag phases                               : %d total = %d unknown + %d known\n',N,nUnknown,nKnown);

fprintf('\n--- Channel / receiver processing ---\n');
fprintf('TGn delay profile                             : %s before, %s after\n',tgnBefore.DelayProfile,tgnAfter.DelayProfile);
fprintf('Injected CFO                                  : %.1f Hz\n',cfoHz);
fprintf('Calibration receiver packet offset            : %d samples\n',cal.pktOffset);
fprintf('Tagged receiver packet offset                 : %d samples\n',rx.pktOffset);
fprintf('Tagged receiver coarse/fine CFO estimates     : %.2f / %.2f Hz\n',rx.coarseFreqOff,rx.fineFreqOff);
fprintf('802.11n PSDU bit errors after Full tag         : %d/%d\n',psduBitErrors,numel(txPSDU));

fprintf('\n--- Full decoder sanity checks ---\n');
fprintf('Calibration H_fH_b compensation error          : %.3e\n',calibrationCompError);
fprintf('Matrix model error, z vs alpha*A*v             : %.3e\n',modelError);
fprintf('Pilot/Gamma compensation model error           : %.3e\n',pilotCompError);
fprintf('Decoder residual phase c angle                 : %.3f rad\n',angle(bestC));
fprintf('Decoder hard-search cost                       : %.3e\n',bestCost);

fprintf('\n--- Full TScatter tag decode result ---\n');
fprintf('Full TScatter tag errors                       : %d/%d\n',tagBitErrors,nUnknown);
fprintf('Full TScatter tag BER                          : %.4f\n',tagBitErrors/nUnknown);

%% Local helper functions
function ch = makeTGnChannel(~,fs,seed,numTx,numRx,distanceMeters)
%MAKETGNCHANNEL Reproducible SISO TGn channel used by this packet simulation.
    ch = wlanTGnChannel;
    ch.DelayProfile = 'Model-B';
    ch.NumTransmitAntennas = numTx;
    ch.NumReceiveAntennas = numRx;
    ch.TransmitReceiveDistance = distanceMeters;
    ch.LargeScaleFadingEffect = 'None';
    ch.NormalizeChannelOutputs = false;
    ch.NormalizePathGains = true;
    ch.SampleRate = fs;
    ch.RandomStream = 'mt19937ar with seed';
    ch.Seed = seed;

    % Keep the channel realization static over one packet. This makes the
    % OFDM diagonal channel model meaningful inside the packet.
    if isprop(ch,'EnvironmentalSpeed')
        ch.EnvironmentalSpeed = 0;
    end
end

function [pktOffset,state] = packetOffsetForFieldAccess(rx,cfgHT)
%PACKETOFFSETFORFIELDACCESS Locate a packet enough to index HT-Data samples.
    state = struct('detectionError',false,'coarsePktOffset',[], ...
        'finePktOffset',[],'coarseFreqOff',[]);
    ind = wlanFieldIndices(cfgHT);
    fs = wlanSampleRate(cfgHT);

    coarsePktOffset = wlanPacketDetect(rx,cfgHT.ChannelBandwidth);
    if isempty(coarsePktOffset)
        pktOffset = NaN;
        state.detectionError = true;
        return;
    end

    lstf = rx(coarsePktOffset+(ind.LSTF(1):ind.LSTF(2)),:);
    coarseFreqOff = wlanCoarseCFOEstimate(lstf,cfgHT.ChannelBandwidth);
    rxCoarseCorrected = frequencyOffset(rx,fs,-coarseFreqOff);

    nonhtfields = rxCoarseCorrected(coarsePktOffset+(ind.LSTF(1):ind.LSIG(2)),:);
    finePktOffset = wlanSymbolTimingEstimate(nonhtfields,cfgHT.ChannelBandwidth);
    pktOffset = coarsePktOffset + finePktOffset;

    state.coarsePktOffset = coarsePktOffset;
    state.finePktOffset = finePktOffset;
    state.coarseFreqOff = coarseFreqOff;
end

function state = receiveHTPacket(rx,cfgHT)
%RECEIVEHTPACKET 802.11n HT receiver chain for one packet.
    state = struct('detectionError',false,'rxPSDU',[],'eqDataSym',[], ...
        'chanEst',[],'htdata',[],'pktOffset',NaN,'coarsePktOffset',NaN, ...
        'finePktOffset',NaN,'coarseFreqOff',NaN,'fineFreqOff',NaN, ...
        'noiseVar',NaN);

    fs = wlanSampleRate(cfgHT);
    ind = wlanFieldIndices(cfgHT);

    coarsePktOffset = wlanPacketDetect(rx,cfgHT.ChannelBandwidth);
    if isempty(coarsePktOffset)
        state.detectionError = true;
        return;
    end

    lstf = rx(coarsePktOffset+(ind.LSTF(1):ind.LSTF(2)),:);
    coarseFreqOff = wlanCoarseCFOEstimate(lstf,cfgHT.ChannelBandwidth);
    rx = frequencyOffset(rx,fs,-coarseFreqOff);

    nonhtfields = rx(coarsePktOffset+(ind.LSTF(1):ind.LSIG(2)),:);
    finePktOffset = wlanSymbolTimingEstimate(nonhtfields,cfgHT.ChannelBandwidth);
    pktOffset = coarsePktOffset + finePktOffset;

    if pktOffset < 0 || pktOffset+ind.HTData(2) > size(rx,1)
        state.detectionError = true;
        return;
    end

    lltf = rx(pktOffset+(ind.LLTF(1):ind.LLTF(2)),:);
    fineFreqOff = wlanFineCFOEstimate(lltf,cfgHT.ChannelBandwidth);
    rx = frequencyOffset(rx,fs,-fineFreqOff);

    htltf = rx(pktOffset+(ind.HTLTF(1):ind.HTLTF(2)),:);
    htltfDemod = wlanHTLTFDemodulate(htltf,cfgHT);
    chanEst = wlanHTLTFChannelEstimate(htltfDemod,cfgHT);

    htdata = rx(pktOffset+(ind.HTData(1):ind.HTData(2)),:);
    if exist('htNoiseEstimate','file') == 2
        nVarHT = htNoiseEstimate(htdata,chanEst,cfgHT);
    else
        nVarHT = 1e-12;
    end

    [rxPSDU,eqDataSym] = wlanHTDataRecover(htdata,chanEst,nVarHT,cfgHT, ...
        'EqualizationMethod','ZF', ...
        'PilotPhaseTracking','None');

    state.rxPSDU = rxPSDU;
    state.eqDataSym = eqDataSym;
    state.chanEst = chanEst;
    state.htdata = htdata;
    state.pktOffset = pktOffset;
    state.coarsePktOffset = coarsePktOffset;
    state.finePktOffset = finePktOffset;
    state.coarseFreqOff = coarseFreqOff;
    state.fineFreqOff = fineFreqOff;
    state.noiseVar = nVarHT;
end

function W = shiftedDFTMatrix(N)
%SHIFTEDDFTMATRIX Matrix form of fftshift(fft(x)).
    k = (0:N-1).';
    n = 0:N-1;
    F = exp(-1j*2*pi*(k*n)/N);
    W = fftshift(eye(N),1) * F;
end

function X = ofdmBlocksToFreq(samples,N,Ncp,W)
%OFDMBLOCKSTOFREQ Convert CP-included OFDM blocks to shifted FFT bins.
    Nblock = N + Ncp;
    nSym = floor(size(samples,1)/Nblock);
    X = zeros(N,nSym);
    for symIdx = 1:nSym
        rows = (symIdx-1)*Nblock + (1:Nblock);
        block = samples(rows,1);
        useful = block(Ncp+1:end);
        X(:,symIdx) = W * useful;
    end
end

function alpha = bestComplexScale(model,observed)
%BESTCOMPLEXSCALE Least-squares scalar alpha for observed ~= alpha*model.
    alpha = (model' * observed) / (model' * model);
end

function [vBest,costBest,cBest] = refineHard(vStart,unknownMask,A,gammaRow,y,costStart,cStart)
%REFINEHARD Coordinate refinement over v_i in {+1,-1}.
    vBest = vStart;
    costBest = costStart;
    cBest = cStart;
    slots = find(unknownMask);
    for pass = 1:4
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
