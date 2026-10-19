# v1.1.0 validation / 验证记录

## Result / 结果

Local validation completed for implementation `a4451eb`: **54 core tests in 7 suites, 18 native runtime groups**, universal packaging, bilingual exports, real network/storage samples and original-artwork regressions passed. Publication and downloaded-release checks will be recorded after delivery. Machine-readable evidence and all per-run aggregates are in [telemetry-plus-validation.json](telemetry-plus-validation.json).

本地验证已通过：54 项核心测试、18 组原生检查、双架构打包、中英文界面导出、真实网络／存储采样及原图案回归。公开发布与下载包检查在交付后补充，未执行的步骤不计为已通过。

## Scope / 覆盖范围

- Native 64-bit network counters: first/reset/missing samples, interface changes, observed-session totals and safe buffer parsing; storage capacity ordering and APFS Data semantics.
- Old preferences, bounded profile/rule migration, practical units, strict thresholds, baseline/hold/cooldown/rearm and missing/disabled/wake invalidation.
- Shared Unicode limits: names 32 characters / 1,024 UTF-8 bytes, IDs 64 characters / 256 bytes; whole graphemes retained. A 27,182-byte maximum-count family-emoji configuration now survives 8,192-byte real-Pipe fragments. The 131,072-byte per-frame budget is enforced at sender/receiver; oversized complete/fragmented frames drain and recover, exact-limit and coalesced frames deliver, and actual child close/reopen agrees with resident preferences.
- One serial async worker with one inflight plus one coalesced request, main-thread responsiveness under a blocked read, generation rejection, module reset epochs and owner release.
- Seven lazy settings pages, five telemetry pages, valid pending/marked IME commit, invalid draft preservation while the helper lives, untouched scalar precision, preview routing, restored presets and language switching.
- Actual child-process IPC, final-write/close acknowledgment, highest-tab reopen, parent EOF exit, capped 300-point graphs, stopped header timers, bounded alert queue and power interruption.

Commands: `bash scripts/test.sh`, `bash scripts/check-runtime.sh`, `bash scripts/build-app.sh --universal`. The native passing groups are retained in [runtime output](telemetry-plus-runtime-checks.txt). The Unicode fix passed 54 core tests and 18 native groups. A subsequent test-only storage-fixture correction also passed all 54 core tests; production code remained unchanged from `c910180`. The fresh universal binary and its SHA256 are the same binary used for the candidate measurements.

## Visual and language checks / 图案与双语

The five original artwork files remain byte-identical. Three fixed battery PNGs also match the pre-feature baseline byte-for-byte:

| Frame | SHA256 |
| --- | --- |
| Title 1.55 s | `86250dc770e1b1a14751bd40e1f9ea59eda1db82f4e05950e0f0f42aab4d55ab` |
| Numbers 3 s / reduced 0.15 s | `206f83823493a18d9793e505b781b3a748695fd0480b25e8d713815459443696` |

The packaged 1024×1024 app icon decodes to the exact source pixels; menu artwork is unchanged. Native EN/ZH exports cover all five terminal and seven settings pages, custom capsules, disabled/unavailable inputs and Reduce Motion. New EN/ZH pages, editor controls and scrolled rule notes were visually inspected. Settings screenshots omit system title/toolbar chrome; actual navigation is covered by native-window checks.

功能导航和控件支持中文／English／跟随系统，固定品牌字样、单位与用户自定标题不自动翻译。默认电量三段画面及五份图案资源完全一致；新页面保留炭黑、灰白、黄绿色，未知值不会伪装为零。

## Comparable measurements / 同口径测量

Host: **MacBook Air M5 / Mac17,3, 16 GiB, macOS 27.0.1 (26A434)**. Three cold starts per scenario, 0.3 s launch settle, 200 ms samples. Memory is the sum of `ri_phys_footprint` for resident plus direct UI children; table values are median final samples. Peaks are the highest observed sample over all runs, not instantaneous maxima. The UI-exit scenario terminates only the owned helper; actual window-close behavior is separately covered by the native suite.

| Scenario / 场景 | v1.0.2 MiB | v1.1.0 MiB | v1.1.0 sampled peak MiB |
| --- | ---: | ---: | ---: |
| Idle / 空闲 | 12.42 | 11.53 | 11.75 |
| Settings / 设置 | 44.06 | 43.96 | 44.06 |
| Battery animation end / 电量动画结束 | 15.42 | 15.13 | 17.45 |
| Telemetry / 遥测 | 56.66 | 56.21 | 96.16 |
| After UI helper exit / 界面进程退出后 | 12.20 | 11.64 | 11.81 |

No sustained resident growth was observed in these scenarios. All candidate runs, including their peaks and variation, are retained; no outlier was excluded. Settings and telemetry defaults were measured; this is not a worst-case bound for every profile/rule/editor combination. System load, font caches, memory pressure and power mode are not controlled laboratory conditions; small differences are not proof of a performance gain.

这些场景未观察到持续常驻增长，但短时峰值高于末值。所有逐轮数据和峰值均保留，没有删去异常值。这里测量的是默认设置页与电源遥测页，不代表所有配置的最坏情况，也不将小幅差异归因于优化效果。

The following are baseline/candidate medians from same-PID deltas over the last 12 samples (~2.2 s). CPU 100% means one core; wakeup counters are kernel proxies. They are **not direct battery-energy measurements**. The animation interval can still include active animation.

| Scenario / 场景 | CPU% old / new | Package idle wakes/s old / new | Interrupt wakes/s old / new |
| --- | ---: | ---: | ---: |
| Idle / 空闲 | 0.045 / 0.023 | 0.45 / 0.00 | 0.45 / 0.45 |
| Settings / 设置 | 0.043 / 0.035 | 0.45 / 0.45 | 0.89 / 0.89 |
| Battery animation end / 电量动画结束 | 1.016 / 1.381 | 7.55 / 4.89 | 10.27 / 11.20 |
| Telemetry / 遥测 | 0.402 / 0.500 | 1.33 / 0.89 | 4.01 / 4.46 |
| After UI helper exit / 界面进程退出后 | 0.007 / 0.007 | 0.00 / 0.00 | 0.45 / 0.45 |

## Local package / 本地安装包

- Version 1.1.0/build 4; macOS 13 deployment; arm64+x86_64; en+zh-Hans bundle declarations.
- Executable: **1,539,184 B**; ZIP: **932,231 B**; 10 real bundle files.
- ZIP SHA256: `f7ef6495275ee26c7eb87c370e45d716eaf03a11724eae85baff74446da3950d`.
- Strict ad-hoc signature, executable permission, archive integrity/safe paths, all-file byte equality, privacy manifest and bundled licenses verified.
- A real packaged-executable snapshot supplied all five modules; network rates were finite/nonnegative and `0≤available≤free≤total` held for storage. Personal readings are not published.

Runtime validation used the local M5/macOS 27.0.1 host. Both target slices linked and signed, but Intel/macOS 13 execution was not performed; Rosetta is absent. Local CLT emits an inherited native-build-engine deprecation and an arm-only compatibility-archive warning for the x86_64 link. These are retained as build limitations rather than hidden as clean output. CI/public archive verification follows publication.

本地安装包已验证双架构、签名、权限、ZIP 完整性、逐文件一致性、隐私声明与许可；不发布本机原始遥测。Intel/macOS 13 尚无实机执行验证，本机未安装 Rosetta。现有工具链警告如实保留；公开CI产物检查另行记录。
