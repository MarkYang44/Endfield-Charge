# v1.2.0 capsule sharing and presentation validation

Local candidate verified on 2026-10-21. Version **1.2.0 / build 5**. Final whole-branch review, main integration, public release/download verification and installation are separate delivery steps; this record does not claim they have happened.

## Functional evidence

- `bash scripts/test.sh`: **108 tests across 10 suites pass**.
- `bash scripts/check-runtime.sh`: **24 native groups pass**, including actual AppKit controls/marked IME drafts, resident-authoritative import revisions, backup failure preservation, cancel/undo, deferred close/rapid reopen, real child-process pipes/EOF/exit, live sampler demand and static HUD lifecycle.
- `ENDFIELD_EDITORS_ONLY=1 bash scripts/check-runtime.sh`: popup caption regression reproduced RED before the fix and GREEN afterward. Renaming the selected capsule refreshes both available and queued captions immediately, without a page rebuild.
- The maximum real-pipe fixture now contains 12 profiles, 48 ordered color conditions, 16 mixed numeric/state rules and a 12-item queue. Names reach 32 graphemes/1024 UTF-8 bytes and custom/rule IDs 64 graphemes/256 bytes. Production SettingsChannel transports fragmented 8192-byte writes and coalesced messages; exact 128 KiB acceptance, oversized drain/recovery and final ordered flush are retained.
- Existing native checks independently assert that settled persistent single display has no animation/rotation timer, reduced motion preserves dwell, hiding releases demand, wake waits for fresh data, invalid rules/configuration do not replay stale content, power has priority and UI owners release on close. Footprint samples alone do not prove these properties.
- `bash scripts/build-app.sh --universal`: Apple Silicon and Intel release slices build; About shows 1.2.0 and the bundle declares 1.2.0/build 5. The native checks ran before the version-only About literal changed; the universal build covers that final literal.

Prior task-scoped reviews found no Critical/Important issues. The Task 5 Minor live-caption issue is resolved with actual-control RED/GREEN. Final whole-branch review remains a controller delivery checkpoint.

## Visual regression and demo exports

All five original/derived source artwork SHA-256 hashes match the pre-feature baseline. Three production battery PNG exports also match byte-for-byte: stage 1.55 title, stage 3 numbers and stage 0.15 with Reduce Motion. Artwork and export hashes are in the [machine-readable record](capsule-sharing-validation.json).

Actual English/Chinese settings and HUD exports use isolated synthetic preferences/readings. The [configuration guide](configuration-sharing.md) and [中文指南](configuration-sharing.zh-CN.md) show real AppKit content captures (system title bar/toolbar excluded), sharing preview, scrolled condition/state/queue sections, first-matched amber color, serious thermal and warning memory-pressure labels. These are demo images, not live telemetry or edited/mock UI. Published images were visually inspected for readable controls and no state/number/title overlap; scroll viewport edges can omit adjacent content, shown in neighboring captures.

Reproduce editor/HUD exports with:

```bash
ENDFIELD_EDITORS_ONLY=1 ENDFIELD_EDITOR_SCREENSHOTS=/tmp/endfield-demo bash scripts/check-runtime.sh
```

The unchanged battery commands use the packaged executable with `--render /tmp/battery.png --demo --stage 1.55`, stage `3`, or stage `0.15 --reduce-motion`.

## Physical footprint and CPU

Host: Apple M5, 16 GiB, arm64, macOS 27.0.1 (26A434). Three fresh process starts per scenario, 200 ms sampling after a 0.3-second launch settle. Sum **ri_phys_footprint of resident plus direct UI children**, not RSS. Report median of three final samples, maximum observed peak across runs, and median whole-run CPU from first to last sample across matching PIDs, excluding the initial 0.3-second settle; 100% means one core. Observations: idle/settings/helper-exit 5 seconds, transient carousel 45 seconds, persistent single 35 seconds, persistent carousel 45 seconds. Nominal windows include probe overhead.

| Scenario | v1.1.0 final median MiB | Candidate final median MiB | Candidate sampled peak MiB | Whole-run CPU % of one core |
| --- | ---: | ---: | ---: | ---: |
| Default idle | 11.470 | 11.735 | 11.860 | 0.0145 |
| Settings open | 42.533 | 48.314 | 82.752 | 0.3695 |
| After settings helper exits | — | 11.642 | 11.766 | 0.0042 |
| Transient carousel | — | 16.220 | 19.767 | 2.7229 |
| Persistent single | — | 14.407 | 16.032 | 1.0284 |
| Persistent carousel | — | 17.532 | 18.001 | 1.6734 |

The earlier freshly collected v1.1.0 installed-app baseline uses the same host, probe, interval, settle and five-second default windows. It is a sequential comparison under uncontrolled system/cache/thermal conditions, not a controlled causal experiment. Settings can retain startup/font caches during this short window. New display modes are separate workloads and have no equivalent baseline row. Sampled peaks can miss shorter events, and CPU averages do not measure energy or battery consumption. Final-12-sample tail CPU is retained separately in JSON and is phase-sensitive: carousel sampling can end during a finite transition, so that tail is not a whole-mode average. This is not a promise of zero incremental memory, CPU or battery use.

The development-only `profile-candidate.py` harness called the packaged app with three runs per scenario. It seeds canonical built-in CPU/network/storage profiles, all modules enabled, no custom rules, 15-second queue dwell; unrelated built-in alerts are disabled for the display-mode scenarios. Persistent single uses CPU; carousel uses CPU/network/storage. Default scenarios retain legacy local presentation preferences with all new display features off. Real preferences are freshly exported and restored in `finally`, and the unchanged installed v1.1.0 app is reopened afterward. Post-helper-exit footprint uses SIGTERM to the owned settings helper, while real user-close/ACK/exit behavior is tested separately by the native suite. Only aggregates/methods are published; raw preference backups and telemetry stay private.

The measured executable SHA-256 was `d4bd0eb26e1668c556de03b58c81b589171835297192b681c4c15fe20d2b1166`. After measuring, only the bundled notice's upstream paths were expanded, then the app was resealed/repacked. Both architectures' complete `__TEXT` segments and executable sections are unchanged; [the JSON record](capsule-sharing-validation.json) includes that comparison. Final archive/signature hashes therefore differ from the measured package's signature hash. No claim is made that a later CI download is byte-identical to this local candidate.

## Final local package

- Universal slices: `x86_64, arm64`. Bundle minimum macOS 13.0; both LC_BUILD_VERSION records declare 13.0. Intel/macOS 13 physical execution has not been tested on this host.
- Executable: 2,282,544 bytes; SHA-256 `1a91cedaea8b800a9a7e956964727bc31f3de23b0c5a96d2dea9fb72ff54d12f`.
- ZIP: 1,240,558 bytes; SHA-256 `256212cde2c4fd4a861896675d0a941039b0698787f8507549ed1b0449f65861`.
- Strict/deep ad-hoc signature verification passes. ZIP integrity, safe relative paths and packaged executable equality pass.
- LICENSE, THIRD_PARTY_NOTICES.md, exact GlacierGlimmer MIT text and PrivacyInfo.xcprivacy are bundled and match source. Source artwork and packaged menu/wordmark resources match their originals. Dependencies are system frameworks/libraries; no .NET/Web/Python runtime, extra font/game assets, preferences or raw telemetry are in the archive.

## Defaults, migration and recovery

Old preferences and shortcut migrate without enabling colors, persistent display or rotation. New/imported rules start disabled; replace import turns playback switches off, merge preserves local enabled switches. Sharing excludes local preferences/readings; undo restores one full pre-import snapshot without altering macOS login registration. Files/private frames are bounded to 128 KiB; share decoding is strict and versioned, separate from tolerant old preferences. Arbitrary upstream Plus JSON is not supported. See the bilingual guides for first-match color, baseline/cooldown/unknown semantics, thirty-second background gaps, queue/power/hide/sleep behavior and limits.

## 中文摘要

本记录验证本地 1.2.0/build 5 候选包：108 项核心测试、24 组原生检查、双架构 macOS 13 声明与严格签名通过。5 个图案与 3 张原电池阶段 PNG 哈希未变；新增中英文真实界面使用合成演示数据。上表为常驻＋直接界面子进程 physical footprint 的三轮末值中位数，不是 RSS 或通用内存保证。系统活动与缓存未受控，峰值仅为采样观测；新轮播／常驻场景不能与旧默认空闲直接等同。测量后仅展开了打包声明中的上游路径并重新签名，两架构 __TEXT／代码段完全不变，完整签名哈希相应改变。公开文件只含汇总与方法，无真实偏好或原始遥测。最终整分支审查、公开下载核验及安装由后续交付步骤完成。
