# Full TScatter on 802.11n SISO

This folder contains the 802.11n SISO implementation of Full TScatter.

Main entry:

```matlab
Full_TScatter_80211n_SISO
```

## Scope

This is not the mathematics-only proof of concept.  The math-only Full
TScatter derivation is in:

```text
../Proof-of-Concept_Simulation/Full_TScatter_PoC.m
```

This folder uses a packet-level 802.11n HT 20 MHz SISO configuration:

```text
ChannelBandwidth        = CBW20
NumTransmitAntennas     = 1
NumSpaceTimeStreams     = 1
MCS                     = 7
GuardInterval           = Long
```

The implementation is no longer only an HT-like dimension check.  It uses
the MATLAB WLAN Toolbox PHY chain:

```text
wlanWaveformGenerator
Tx -> tag TGn channel
Full TScatter modulation on one HT-Data OFDM symbol
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

This receiver flow follows the structure of the official MathWorks 802.11n
TGn packet-error-rate example, specialized to SISO and with the TScatter tag
operation inserted into HT-Data.

## Full TScatter model

The script keeps the Full TScatter matrix model visible:

```text
y = exp(j*beta) H_b W D(v) W^{-1} H_f x
z = (H_f H_b)^(-1) y
z = exp(j*beta) A v
```

It also checks pilot/Gamma compensation:

```text
zbar ~= c(v) A v
```

## Channel compensation and calibration

The tag decoder does not assume a flat channel.  It estimates:

```text
H_f      : Tx -> tag frequency-selective channel
H_f H_b  : Tx -> tag -> Rx cascade
```

using a same-realization calibration packet.  This is why the script resets
the TGn channel with fixed seeds before the calibration and tagged packets.
The standard HT-LTF channel estimate is still computed by the receiver, but
the Full tag decoder uses the calibration packet so the matrix model can
stay close to the paper-level `H_f`, `H_b`, and `A` derivation.

The script also prints ordinary PSDU bit errors after Full tag modulation.
Those errors are expected to be nonzero because the standard 802.11n
receiver is not TScatter-aware.  The relevant Full TScatter metric is the
final tag error count.  In the default high-SNR smoke test, the expected
result is `0/48` tag errors.
