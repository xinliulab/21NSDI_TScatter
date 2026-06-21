# TScatter MATLAB Simulations

This repository contains compact MATLAB simulations for the NSDI 2021 paper
**Verification and Redesign of OFDM Backscatter**.  The code is organized to
make the TScatter signal model easy to inspect first, and then to show the
same ideas inside an 802.11n SISO packet-level simulation.

Paper: [USENIX NSDI 2021 paper page](https://www.usenix.org/conference/nsdi21/presentation/liu-xin)

## Repository layout

| Folder | Purpose | Main scripts |
| --- | --- | --- |
| `Proof-of-Concept_Simulation` | Mathematics-only proof-of-concept simulations. No 802.11n protocol stack. | `Full_TScatter_PoC.m`, `Lite_TScatter_PoC.m` |
| `Full_TScatter` | Packet-level Full TScatter simulation on 802.11n HT 20 MHz SISO. | `Full_TScatter_80211n_SISO.m` |
| `Lite_TScatter` | Packet-level Lite TScatter simulation on 802.11n HT 20 MHz SISO. | `Lite_TScatter_80211n_SISO.m` |

## What the simulations show

The math PoC scripts expose the core equations directly:

```text
y = exp(j beta) H_b W D(v) W^{-1} H_f x
z = (H_f H_b)^{-1} y
z = exp(j beta) A v
```

The Full PoC uses 64 useful time samples, 48 unknown sample-level tag phases,
and 16 known/predefined phases.  The Lite PoC uses one tag phase per OFDM
block.

The packet-level scripts use MATLAB WLAN Toolbox components in the style of
the MathWorks 802.11n TGn packet-error-rate example:

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

Reference example:
[802.11n Packet Error Rate Simulation for 2x2 TGn Channel](https://www.mathworks.com/help/wlan/ug/802-11n-packet-error-rate-simulation-for-2x2-tgn-channel.html).

The packet-level tag decoders use same-realization calibration packets to
estimate frequency-selective `H_f` and/or `H_f H_b` compensation terms.  This
keeps the simulation close to the paper-level channel model while still using
MATLAB's realistic 802.11n receiver pipeline.

## Requirements

- MATLAB
- WLAN Toolbox
- Communications Toolbox, for functions such as `awgn` and `frequencyOffset`

The current scripts were smoke-tested with MATLAB R2024b.

## Quick start

From MATLAB, run:

```matlab
cd Proof-of-Concept_Simulation
Full_TScatter_PoC
Lite_TScatter_PoC

cd ../Full_TScatter
Full_TScatter_80211n_SISO

cd ../Lite_TScatter
Lite_TScatter_80211n_SISO
```

Expected high-SNR smoke-test behavior:

```text
Full_TScatter_PoC              -> 0/48 tag errors
Lite_TScatter_PoC              -> 0/8 tag errors
Full_TScatter_80211n_SISO      -> 0/48 tag errors
Lite_TScatter_80211n_SISO      -> 0/8 tag errors
```

The 802.11n scripts also print ordinary PSDU bit errors after tag modulation.
Those errors are not the TScatter tag-decoding metric; they show what a
standard WiFi receiver sees before any TScatter-aware payload repair.

## Citation

If you use this code or build on TScatter, please cite:

```bibtex
@inproceedings {tscatter,
    author = {Xin Liu and Zicheng Chi and Wei Wang and Yao Yao and Pei Hao and Ting Zhu},
    title = {Verification and Redesign of {OFDM} Backscatter},
    booktitle = {18th USENIX Symposium on Networked Systems Design and Implementation (NSDI 21)},
    year = {2021},
    isbn = {978-1-939133-21-2},
    pages = {939--953},
    url = {https://www.usenix.org/conference/nsdi21/presentation/liu-xin},
    publisher = {USENIX Association},
    month = apr
}
```

## License

This repository is released under the MIT License.  See [LICENSE](LICENSE).

---

# TScatter MATLAB 仿真

这个仓库包含 NSDI 2021 论文 **Verification and Redesign of OFDM Backscatter**
的精简 MATLAB 仿真代码。仓库的目标是先用最小数学脚本把 TScatter 的信号模型讲清楚，
再把同样的机制放进 802.11n SISO 的 packet-level 仿真链路里验证。

论文入口：[USENIX NSDI 2021 paper page](https://www.usenix.org/conference/nsdi21/presentation/liu-xin)

## 仓库结构

| 文件夹 | 作用 | 主脚本 |
| --- | --- | --- |
| `Proof-of-Concept_Simulation` | 纯数学 proof-of-concept 仿真，不使用 802.11n 协议栈。 | `Full_TScatter_PoC.m`, `Lite_TScatter_PoC.m` |
| `Full_TScatter` | Full TScatter 在 802.11n HT 20 MHz SISO 上的 packet-level 仿真。 | `Full_TScatter_80211n_SISO.m` |
| `Lite_TScatter` | Lite TScatter 在 802.11n HT 20 MHz SISO 上的 packet-level 仿真。 | `Lite_TScatter_80211n_SISO.m` |

## 这些仿真证明了什么

数学 PoC 直接展示核心矩阵关系：

```text
y = exp(j beta) H_b W D(v) W^{-1} H_f x
z = (H_f H_b)^{-1} y
z = exp(j beta) A v
```

Full PoC 使用 64 个 useful time samples，其中 48 个 sample-level tag phases
是未知量，16 个 phase 是已知/预定义量。Lite PoC 则是每个 OFDM block 一个 tag phase。

802.11n 脚本使用 MATLAB WLAN Toolbox 的真实接收流程，结构参考 MathWorks 的
802.11n TGn packet-error-rate 示例：

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

参考示例：
[802.11n Packet Error Rate Simulation for 2x2 TGn Channel](https://www.mathworks.com/help/wlan/ug/802-11n-packet-error-rate-simulation-for-2x2-tgn-channel.html)。

packet-level 的 tag decoder 使用 same-realization calibration packet 来估计
频率选择性的 `H_f` 和/或 `H_f H_b` 补偿项。这样既保留论文中的信道补偿模型，
又使用了 MATLAB 较真实的 802.11n 接收链路。

## 运行环境

- MATLAB
- WLAN Toolbox
- Communications Toolbox，例如 `awgn` 和 `frequencyOffset`

当前脚本已经在 MATLAB R2024b 下做过 smoke test。

## 快速运行

在 MATLAB 中运行：

```matlab
cd Proof-of-Concept_Simulation
Full_TScatter_PoC
Lite_TScatter_PoC

cd ../Full_TScatter
Full_TScatter_80211n_SISO

cd ../Lite_TScatter
Lite_TScatter_80211n_SISO
```

高 SNR 默认设置下，预期 smoke-test 结果是：

```text
Full_TScatter_PoC              -> 0/48 tag errors
Lite_TScatter_PoC              -> 0/8 tag errors
Full_TScatter_80211n_SISO      -> 0/48 tag errors
Lite_TScatter_80211n_SISO      -> 0/8 tag errors
```

802.11n 脚本还会打印 tag modulation 后普通 PSDU 的 bit errors。这个不是
TScatter tag decoding 的指标；它只是说明标准 WiFi receiver 在不知道 tag phase
时会看到 payload 被扰动。真正应该看的指标是最后的 tag error count。

## 引用

如果你使用这个代码或者基于 TScatter 做后续研究，请引用：

```bibtex
@inproceedings {tscatter,
    author = {Xin Liu and Zicheng Chi and Wei Wang and Yao Yao and Pei Hao and Ting Zhu},
    title = {Verification and Redesign of {OFDM} Backscatter},
    booktitle = {18th USENIX Symposium on Networked Systems Design and Implementation (NSDI 21)},
    year = {2021},
    isbn = {978-1-939133-21-2},
    pages = {939--953},
    url = {https://www.usenix.org/conference/nsdi21/presentation/liu-xin},
    publisher = {USENIX Association},
    month = apr
}
```

## License

本仓库使用 MIT License 发布。详见 [LICENSE](LICENSE)。
