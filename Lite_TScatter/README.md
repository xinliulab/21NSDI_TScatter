# Lite TScatter on 802.11n SISO

This folder contains the 802.11n SISO implementation of Lite TScatter.

Main entry:

```matlab
Lite_TScatter_80211n_SISO
```

## Scope

The old Lite/VMscatter code in this repository used a larger 2x2 MIMO/STC
demo.  This folder is now a readable SISO version, but it still uses a real
802.11n packet-level receiver chain rather than a pure math shortcut.

The math-only Lite TScatter explanation is in:

```text
../Proof-of-Concept_Simulation/Lite_TScatter_PoC.m
```

This folder uses an 802.11n HT 20 MHz SISO configuration:

```text
ChannelBandwidth        = CBW20
NumTransmitAntennas     = 1
NumSpaceTimeStreams     = 1
MCS                     = 7
GuardInterval           = Long
```

## Receiver chain

The main script follows the same receiver structure as the official
MathWorks 802.11n TGn packet-error-rate example, specialized to SISO:

```text
wlanWaveformGenerator
Tx -> tag TGn channel
Lite TScatter block-level modulation on HT-Data OFDM blocks
tag -> Rx TGn channel
receiver-side CFO injection
wlanPacketDetect
wlanCoarseCFOEstimate / frequencyOffset
wlanSymbolTimingEstimate
wlanFineCFOEstimate / frequencyOffset
wlanHTLTFDemodulate
wlanHTLTFChannelEstimate
wlanHTDataRecover
```

## Lite model

Lite TScatter uses one tag phase per whole OFDM block:

```text
64 useful samples + 16 CP samples = 80 samples
one Lite tag phase b_m in {+1,-1} per 80-sample block
```

A predefined reference block removes the common phase.  The following blocks
carry Lite tag bits and are decoded by projecting the compensated received
block onto the known WiFi block.

## Channel compensation and calibration

The decoder estimates the frequency-selective `H_f H_b` cascade using a
same-realization calibration packet, then compensates each active subcarrier
before estimating one scalar Lite tag phase per block.  The first block has
known phase `+1` and removes the residual common phase.

The script also prints ordinary PSDU bit errors after Lite tag modulation.
Those errors are expected to be nonzero because a standard 802.11n receiver
does not know the tag phases.  The relevant Lite TScatter metric is the
final tag error count.  In the default high-SNR smoke test, the expected
result is `0/8` tag errors.
