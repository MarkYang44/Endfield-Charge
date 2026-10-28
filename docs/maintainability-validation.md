# Maintainability refactor validation / 可维护性重构验证

2026-10-28. Baseline `04657eb`; product source `00f48ea`. This is an **unreleased candidate**, still declaring 1.2.0/build 5. The installed stable app was restored after measurement; it was not replaced. [Machine-readable evidence](maintainability-validation.json).

## Changes / 修改

Centralized profile/rule/color limits without merging strict imports and forgiving legacy migration; split native scenarios; extracted pure bilingual telemetry projections and paired graph samples; removed the standalone HUD scheduling queue. Migrated production-path checks exposed a weak callback cleanup gap: coordinator destruction now explicitly releases demand after native teardown. Artwork, geometry, animation timing, defaults, schema and wire budgets remain intact.

收拢配置约束、按职责拆分代码、抽出纯遥测展示模型，并统一到生产 HUD 调度器。另修复协调器析构时漏发空采样需求的问题；保持原设计与配置兼容。

## Focused validation / 定向验证

Before the final selector-only edits, the final product source passed 117 core tests and 24 native groups; universal packaging passed architecture, macOS 13 floor, signature, resources and app/ZIP consistency checks. Those results were reused. After selectors changed, only **20 playback core tests and the 4 HUD/playback groups** were rerun, plus short shell argument/dispatch checks. No later full regression was repeated.

Daily commands select the affected area:

```bash
bash scripts/verify.sh core --filter CapsulePlayback
bash scripts/verify.sh desktop hud
bash scripts/verify.sh package
```

Other native groups are `telemetry`, `sharing`, `editors`, `ipc`; full native checks require explicit `desktop all`. `release` is the explicit complete gate. Useful legacy suites remain available. The manual desktop workflow defaults to HUD and requires a separately provisioned trusted graphical runner; it was not dispatched.

日常按改动选择测试，不默认打开全部窗口或启动全部通信场景。重复生命周期循环从三次减为两次，保留真实重复操作以及唯一的优先级、弱引用释放和重入检查。仅脚本选择器和文档变化后复用已有完整结果。

30 bilingual debug telemetry fixtures at the projection step are byte-identical to the baseline. Four representative final packaged exports—battery title, compact, reduced motion and Chinese network—also match exactly. All six source resources retain their hashes. These are deterministic fixture checks, not a claim covering every possible live reading.

## Compact memory comparison / 简短内存对照

Same Apple Silicon host/toolchain; baseline and candidate measured consecutively using unchanged live preferences. Each scenario has **one cold start**, with 0.5-second settling and 200 ms samples. Values below are the final sampled total `ri_phys_footprint` of resident plus direct UI helpers, in MiB. This is a descriptive quick check, **not** a statistical benchmark or evidence of a memory reduction.

| Scenario | Baseline MiB | Candidate MiB |
| --- | ---: | ---: |
| resident | 11.954 | 12.173 |
| demo | 15.298 | 15.220 |
| telemetry | 57.080 | 57.033 |
| telemetry_helper_exited | 12.267 | 12.235 |

The telemetry-helper-exited sample uses SIGTERM only on the owned helper; actual user close/ACK is covered by the existing native checks. Baseline/candidate universal executable sizes are 2,282,544 / 2,290,256 bytes; ZIPs are 1,240,623 / 1,240,630 bytes. Memory and archive size are essentially unchanged at this sampling resolution; the main result is simpler ownership and easier maintenance.

每个场景只抽样一次，未重跑三轮完整性能矩阵。常驻约 12 MiB，不能据此声称明确省内存；安装包大小基本不变。系统负载、字体缓存和当前设置均会影响读数，原始实时采样保留在本机。用户偏好文件哈希未变，原常驻程序已恢复。

## Limits / 边界

No new runtime/dependency/cache/collector was added. Native execution was on Apple Silicon; Intel and macOS 13 hardware execution were not performed. The app remains ad-hoc signed and not notarized. Existing SwiftPM native-build deprecation, test framework deployment warning and local Intel compatibility-archive warning are recorded as pre-existing toolchain limitations, not new source warnings.
