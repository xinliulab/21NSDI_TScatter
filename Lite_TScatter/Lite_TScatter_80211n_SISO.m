% Lite_TScatter_80211n_SISO.m
%
% Packet-level 802.11n SISO simulation of Lite TScatter.
%
% Lite TScatter is the block-level version: one tag phase b_m in {+1,-1}
% multiplies a whole 802.11n OFDM block, including its 16-sample cyclic
% prefix and 64 useful samples. This script keeps the PHY chain realistic:
%
%   * MATLAB WLAN Toolbox generates a real 802.11n HT packet.
%   * Two reproducible TGn SISO channels model Tx->tag and tag->Rx.
%   * A controllable carrier-frequency offset is added before the receiver.
%   * The receiver performs packet detection, coarse CFO correction,
%     timing synchronization, fine CFO correction, HT-LTF channel estimation,
%     and HT-Data recovery.
%   * A same-channel calibration packet estimates the frequency-selective
%     H_f H_b compensation before Lite tag decoding.
%
% The receiver chain follows the official MathWorks 802.11n TGn PER example
% at a SISO setting. The TScatter modulation and tag-bit recovery are local
% to this script.

clear;
clc;
rng(31);

fprintf('\n');
fprintf('============================================================\n');
fprintf(' Lite TScatter on packet-level 802.11n SISO / TGn channel\n');
fprintf('============================================================\n');

%% 1. 802.11n HT SISO configuration
cfgHT = wlanHTConfig;
cfgHT.ChannelBandwidth = 'CBW20';
cfgHT.NumTransmitAntennas = 1;
cfgHT.NumSpaceTimeStreams = 1;
cfgHT.MCS = 7;
cfgHT.ChannelCoding = 'BCC';
cfgHT.GuardInterval = 'Long';
cfgHT.PSDULength = 512;                % Gives enough HT-Data symbols for Lite bits.

fs = wlanSampleRate(cfgHT);
ofdmInfo = wlanHTOFDMInfo('HT-Data',cfgHT);
ind = wlanFieldIndices(cfgHT);

N = ofdmInfo.FFTLength;
Ncp = ofdmInfo.CPLength;
Nblock = N + Ncp;
nHTDataSamples = ind.HTData(2) - ind.HTData(1) + 1;
nHTDataSymbols = nHTDataSamples / Nblock;

activeRows = ofdmInfo.ActiveFFTIndices(:);

nReference = 1;
nUnknown = 8;
nCarrierSymbols = nReference + nUnknown;
if nHTDataSymbols < nCarrierSymbols
    error('Lite_TScatter:PacketTooShort', ...
        'Need at least %d HT-Data OFDM symbols, but the packet has %d.', ...
        nCarrierSymbols,nHTDataSymbols);
end
carrierSymbols = 1:nCarrierSymbols;

W = shiftedDFTMatrix(N);

%% 2. Generate one real 802.11n packet
txPSDU = randi([0 1],cfgHT.PSDULength*8,1);
tx = wlanWaveformGenerator(txPSDU,cfgHT,'WindowTransitionTime',0);
tx = [tx; zeros(15,cfgHT.NumTransmitAntennas)];

txHTData = tx(ind.HTData(1):ind.HTData(2),:);
txFreq = ofdmBlocksToFreq(txHTData,N,Ncp,W);

%% 3. Reproducible Tx->tag and tag->Rx TGn channels
tgnBefore = makeTGnChannel(cfgHT,fs,303,1,1,3);
tgnAfter = makeTGnChannel(cfgHT,fs,404,1,1,3);

reset(tgnBefore);
rxBeforeTag = tgnBefore(tx);

[tagPktOffset,tagTiming] = packetOffsetForFieldAccess(rxBeforeTag,cfgHT);
if tagTiming.detectionError
    error('Lite_TScatter:TagTimingFailed','The tag could not locate HT-Data.');
end

%% 4. Lite TScatter block-level modulation
trueBits = randi([0 1],nUnknown,1);
bTrue = ones(nCarrierSymbols,1);
bTrue(1) = 1;                          % Reference block is known.
bTrue(2:end) = 2*trueBits - 1;

rxTaggedAtTag = rxBeforeTag;
for ii = 1:nCarrierSymbols
    symIdx = carrierSymbols(ii);
    blockRows = double(tagPktOffset) + double(ind.HTData(1)) + (symIdx-1)*Nblock ...
        + (0:Nblock-1);
    rxTaggedAtTag(blockRows,:) = bTrue(ii) * rxTaggedAtTag(blockRows,:);
end

%% 5. Same-realization calibration and tagged packet through tag->Rx channel
reset(tgnAfter);
rxNoTag = tgnAfter(rxBeforeTag);

reset(tgnAfter);
rxTagged = tgnAfter(rxTaggedAtTag);

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
    error('Lite_TScatter:CalibrationReceiverFailed','Calibration packet receiver failed.');
end
if rx.detectionError
    error('Lite_TScatter:TaggedReceiverFailed','Tagged packet receiver failed.');
end

psduBitErrors = biterr(txPSDU,rx.rxPSDU);

%% 7. H_f H_b compensation and Lite tag decoding
calFreq = ofdmBlocksToFreq(cal.htdata,N,Ncp,W);
rxTaggedFreq = ofdmBlocksToFreq(rx.htdata,N,Ncp,W);

alpha = zeros(nCarrierSymbols,1);
calibrationCompError = zeros(nCarrierSymbols,1);
for ii = 1:nCarrierSymbols
    symIdx = carrierSymbols(ii);

    hcascade = calFreq(activeRows,symIdx) ./ txFreq(activeRows,symIdx);
    zCal = calFreq(activeRows,symIdx) ./ hcascade;
    zTagged = rxTaggedFreq(activeRows,symIdx) ./ hcascade;

    xActive = txFreq(activeRows,symIdx);
    calibrationCompError(ii) = norm(zCal-xActive) / norm(xActive);

    % After channel compensation, a Lite tag is one scalar phase per OFDM
    % block: zTagged ~= alpha_m * xActive.  Block 1 has b=+1 and removes
    % the residual common phase.
    alpha(ii) = (xActive' * zTagged) / (xActive' * xActive);
end

referencePhase = alpha(1) / abs(alpha(1));
relativeTag = alpha ./ referencePhase;
bHat = sign(real(relativeTag));
bHat(bHat==0) = 1;

bitHat = bHat(2:end) > 0;
tagBitErrors = sum(bitHat ~= trueBits);

%% 8. Results
fprintf('\n--- 802.11n SISO configuration ---\n');
fprintf('ChannelBandwidth                              : %s\n',cfgHT.ChannelBandwidth);
fprintf('NumTransmitAntennas                           : %d\n',cfgHT.NumTransmitAntennas);
fprintf('NumReceiveAntennas                            : %d\n',1);
fprintf('NumSpaceTimeStreams                           : %d\n',cfgHT.NumSpaceTimeStreams);
fprintf('MCS / PSDULength                              : %d / %d bytes\n',cfgHT.MCS,cfgHT.PSDULength);
fprintf('HT-Data OFDM symbols                          : %d\n',nHTDataSymbols);
fprintf('Useful / CP / block samples                   : %d / %d / %d\n',N,Ncp,Nblock);
fprintf('Lite tag blocks                               : %d reference + %d unknown\n',nReference,nUnknown);

fprintf('\n--- Channel / receiver processing ---\n');
fprintf('TGn delay profile                             : %s before, %s after\n',tgnBefore.DelayProfile,tgnAfter.DelayProfile);
fprintf('Injected CFO                                  : %.1f Hz\n',cfoHz);
fprintf('Calibration receiver packet offset            : %d samples\n',cal.pktOffset);
fprintf('Tagged receiver packet offset                 : %d samples\n',rx.pktOffset);
fprintf('Tagged receiver coarse/fine CFO estimates     : %.2f / %.2f Hz\n',rx.coarseFreqOff,rx.fineFreqOff);
fprintf('802.11n PSDU bit errors after Lite tag         : %d/%d\n',psduBitErrors,numel(txPSDU));

fprintf('\n--- Lite decoder sanity checks ---\n');
fprintf('Mean calibration H_fH_b compensation error     : %.3e\n',mean(calibrationCompError));
fprintf('Reference residual phase angle                 : %.3f rad\n',angle(referencePhase));

fprintf('\nLite block tag phases: [symbol, true, decoded, real(relativeTag)]\n');
disp(table(carrierSymbols(:),bTrue,bHat,real(relativeTag), ...
    'VariableNames',{'htDataSymbol','truePhase','decodedPhase','metric'}));

fprintf('\n--- Lite TScatter tag decode result ---\n');
fprintf('Lite TScatter tag errors                       : %d/%d\n',tagBitErrors,nUnknown);
fprintf('Lite TScatter tag BER                          : %.4f\n',tagBitErrors/nUnknown);

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
