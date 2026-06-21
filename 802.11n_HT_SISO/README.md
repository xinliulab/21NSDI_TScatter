<a id="english"></a>

# 802.11n HT SISO TScatter Simulations

Language: [English](#english) | [中文](#chinese)

This folder contains the packet-level 802.11n HT 20 MHz SISO simulations for
both Full TScatter and Lite TScatter.

Main scripts:

```matlab
Full_TScatter_80211n_SISO
Lite_TScatter_80211n_SISO
```

## Scope

These scripts are not the mathematics-only proof of concept. The math-only
derivations are in:

```text
../Proof-of-Concept_Simulation/Full_TScatter_PoC.m
../Proof-of-Concept_Simulation/Lite_TScatter_PoC.m
```

This folder uses an 802.11n HT 20 MHz SISO configuration:

```text
ChannelBandwidth        = CBW20
NumTransmitAntennas     = 1
NumReceiveAntennas      = 1
NumSpaceTimeStreams     = 1
GuardInterval           = Long
```

The receiver flow follows the structure of the official MathWorks 802.11n
TGn packet-error-rate example, specialized to SISO:

```text
wlanWaveformGenerator
Tx -> tag TGn channel
TScatter modulation on HT-Data
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

## Full TScatter script

`Full_TScatter_80211n_SISO.m` applies sample-level Full TScatter modulation
to one HT-Data OFDM symbol:

```text
64 useful samples + 16 CP samples
64 sample-level Full TScatter phases
48 unknown phases + 16 known/predefined phases
```

The decoder estimates frequency-selective `H_f` and `H_f H_b` using a
same-realization calibration packet, builds the Full decoder matrix `A`, and
then solves the unknown sample-level tag phases with pilot/Gamma
compensation.

In the default high-SNR smoke test, the expected tag result is:

```text
Full TScatter tag errors: 0/48
```

## Lite TScatter script

`Lite_TScatter_80211n_SISO.m` applies one Lite tag phase to each whole
80-sample HT-Data OFDM block:

```text
64 useful samples + 16 CP samples = 80 samples
1 reference block + 8 unknown tag blocks by default
```

The decoder estimates the frequency-selective `H_f H_b` cascade with a
same-realization calibration packet, compensates each active subcarrier, and
uses the reference block to remove residual common phase.

In the default high-SNR smoke test, the expected tag result is:

```text
Lite TScatter tag errors: 0/8
```

## Note on PSDU bit errors

Both scripts also print ordinary PSDU bit errors after tag modulation. These
errors are expected to be nonzero because a standard 802.11n receiver is not
TScatter-aware. The relevant metric for these scripts is the final tag error
count.

---

<a id="chinese"></a>

# 802.11n HT SISO TScatter 仿真

语言： [English](#english) | [中文](#chinese)

这个文件夹包含 Full TScatter 和 Lite TScatter 在 802.11n HT 20 MHz SISO
上的 packet-level 仿真。

主脚本：

```matlab
Full_TScatter_80211n_SISO
Lite_TScatter_80211n_SISO
```

## 范围

这里不是纯数学 PoC。纯数学推导放在：

```text
../Proof-of-Concept_Simulation/Full_TScatter_PoC.m
../Proof-of-Concept_Simulation/Lite_TScatter_PoC.m
```

本文件夹使用 802.11n HT 20 MHz SISO 配置：

```text
ChannelBandwidth        = CBW20
NumTransmitAntennas     = 1
NumReceiveAntennas      = 1
NumSpaceTimeStreams     = 1
GuardInterval           = Long
```

接收流程参考 MathWorks 官方 802.11n TGn packet-error-rate 示例，并专门化为 SISO：

```text
wlanWaveformGenerator
Tx -> tag TGn channel
HT-Data 上插入 TScatter modulation
tag -> Rx TGn channel
接收端 CFO 注入
wlanPacketDetect
wlanCoarseCFOEstimate / frequencyOffset
wlanSymbolTimingEstimate
wlanFineCFOEstimate / frequencyOffset
wlanHTLTFDemodulate
wlanHTLTFChannelEstimate
wlanHTDataRecover
```

## Full TScatter 脚本

`Full_TScatter_80211n_SISO.m` 在一个 HT-Data OFDM symbol 上做 sample-level
Full TScatter modulation：

```text
64 useful samples + 16 CP samples
64 个 sample-level Full TScatter phases
48 个未知 phases + 16 个已知/预定义 phases
```

decoder 通过 same-realization calibration packet 估计频率选择性的 `H_f` 和
`H_f H_b`，构造 Full decoder matrix `A`，再结合 pilot/Gamma compensation
恢复未知 sample-level tag phases。

默认高 SNR smoke test 的预期结果是：

```text
Full TScatter tag errors: 0/48
```

## Lite TScatter 脚本

`Lite_TScatter_80211n_SISO.m` 对每个完整的 80-sample HT-Data OFDM block
施加一个 Lite tag phase：

```text
64 useful samples + 16 CP samples = 80 samples
默认 1 个 reference block + 8 个未知 tag blocks
```

decoder 用 same-realization calibration packet 估计频率选择性的 `H_f H_b`
cascade，对每个 active subcarrier 做补偿，然后用 reference block 去除残余公共相位。

默认高 SNR smoke test 的预期结果是：

```text
Lite TScatter tag errors: 0/8
```

## 关于 PSDU bit errors

两个脚本都会打印 tag modulation 后普通 PSDU 的 bit errors。这些 bit errors
非零是正常的，因为标准 802.11n receiver 并不知道 TScatter tag phases。
这两个脚本真正要看的指标是最后的 tag error count。
