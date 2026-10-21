# Performance records / 性能记录

These are versioned measurements, not universal memory guarantees. Current candidate results are recorded in [v1.2.0 validation](capsule-sharing-validation.md); [v1.1.0 validation](telemetry-plus-validation.md) remains historical. The historical Chinese records below remain unchanged in meaning.

以下为历史版本测量，不能当作当前版本或所有系统的占用保证。v1.2.0 候选版本的同机对照和新增场景见 [验证记录](capsule-sharing-validation.md)，v1.1.0 记录保留为历史证据。

## v1.2.0 candidate / 候选版本

| Scenario | v1.1.0 final median MiB | Candidate final median MiB | Candidate sampled peak MiB | Whole-run CPU % of one core |
| --- | ---: | ---: | ---: | ---: |
| Default idle | 11.470 | 11.735 | 11.860 | 0.0145 |
| Settings open | 42.533 | 48.314 | 82.752 | 0.3695 |
| After settings helper exits | — | 11.642 | 11.766 | 0.0042 |
| Transient carousel | — | 16.220 | 19.767 | 2.7229 |
| Persistent single | — | 14.407 | 16.032 | 1.0284 |
| Persistent carousel | — | 17.532 | 18.001 | 1.6734 |

Methods, caveats, historical intermediate reseal evidence, final copy-only rebuild limits and aggregates: [validation](capsule-sharing-validation.md), [JSON](capsule-sharing-validation.json). Default scenarios use matching five-second methods; new display modes have separate observation windows. Peaks are sampled, table CPU averages the observed run after launch settling, and system activity is uncontrolled. Phase-sensitive final ~2.2-second CPU values are retained separately in JSON.

测量方法、文案重建限制及历史中间阶段仅资源重新签名证据见上述验证记录。默认场景使用匹配的五秒方法，新增播放场景窗口不同；峰值为采样值，表内 CPU 为启动稳定后观测窗口均值；另存的末尾约 2.2 秒 CPU 对切换阶段敏感，系统活动未受控。

## 内存与体积

设置和遥测界面使用原生 AppKit，并按需以同一可执行文件的独立进程打开；关闭窗口后进程退出，释放系统控件、字体和曲线缓存。常驻部分只有原电池监听/菜单栏/快捷键与低频遥测采集，无第三方运行时。私有管道只传单次采样和偏好，正常关闭在最终状态确认后退出，保留当前会话的页签和窗口位置；主进程无响应时另有 2 秒退出兜底。

遥测版本 `b1e77d1`（图标更新前）的同机三轮冷启动测量如下，采用整个应用进程组的 physical footprint、采样末值中位数：

| 场景 | 遥测加入前 | 遥测版实测 |
| --- | ---: | ---: |
| 空闲常驻 | 11.20 MiB | 11.36 MiB |
| 设置打开 | 42.55 MiB | 41.97 MiB |
| 原电量动画结束后 | 14.33 MiB | 14.44 MiB |
| 遥测终端打开 | — | 55.63 MiB |
| 遥测界面进程退出后 | — | 11.30 MiB |

遥测窗口开场动画有短暂绘图缓存开销，三轮 200 ms 采样的最高观测值为 98.05 MiB。常驻增量约 0.16 MiB；关闭后界面进程退出。详细验证、测量口径和边界见 [遥测验证](telemetry-validation.md)，汇总与完整压缩采样见 [测量数据](telemetry-measurements.json)。该次测量未加入额外包或运行时；当时的双架构可执行文件 980,288 B，ZIP 490,449 B。

此前原生界面释放优化的三轮冷启动测量如下（源码 `599642c`，尚未加入遥测）。采用进程 physical footprint，设置打开时合计主进程与设置进程；每项取采样末值的中位数。

| 场景 | 优化前 | 优化后 |
| --- | ---: | ---: |
| 冷启动空闲 | 11.69 MiB | 11.38 MiB |
| 设置打开 | 34.88 MiB | 42.42 MiB |
| 演示动画结束后 | 14.49 MiB | 14.36 MiB |
| 双架构可执行文件 | 1,359,024 B | 726,576 B |
| 应用磁盘占用（du） | 1,504 KiB | 888 KiB |

设置打开时总占用有所增加，换来关闭后界面缓存能够完整退出；冷启动和动画场景的内存变化较小。完整审查、关闭后实测及测量限制见 [内存审查](memory-audit.md)，三轮记录见 [测量数据](memory-measurements.json)。这不代表所有系统版本都会得到相同数值。

退出正在运行的应用后，可复测整个进程组：

```bash
python3 scripts/profile-memory.py "dist/Endfield Charge.app/Contents/MacOS/EndfieldCharge" /tmp/endfield-memory.json
python3 scripts/profile-memory.py "dist/Endfield Charge.app/Contents/MacOS/EndfieldCharge" /tmp/endfield-telemetry-memory.json --telemetry
```

需要 Python 3 和 Command Line Tools；脚本只用于开发测量，不随应用启动。物理占用、RSS、虚拟地址空间和 `.build` 编译缓存采用不同口径，不能混作软件运行内存。
