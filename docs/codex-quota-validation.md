# v1.3.0 delivery / 交付记录

Source/tag: `172044ac330060cbe84af3c6b7ca7672a278ab2f` / `v1.3.0`. [Release](https://github.com/MarkYang44/Endfield-Charge/releases/tag/v1.3.0) · [successful tag build](https://github.com/MarkYang44/Endfield-Charge/actions/runs/40710226941).

- One combined read-only task/feature review approved, no Critical/Important findings.
- Four focused Codex core checks and the native Codex group passed. Existing unrelated native groups/performance matrices were not repeated. Tag CI passed core tests, universal build and package validation.
- Both new Settings choices and menu shortcut are checked against draft/pending/capacity guards; the five existing defaults remain unchanged. Parser, cache, nonblocking collection, cancellation, generation, bounded stdio, SIGPIPE, timeout/reaping and neutral cwd have focused checks.
- Three battery exports (title, compact, Reduce Motion) are byte-identical to the previous baseline. New previews use synthetic data; no live account/quota values are published.
- The independent public download passed digest, ZIP, arm64/x86_64, macOS 13.0 floor, strict ad-hoc signature, expected resources and extracted-app/archive equality checks. Local and CI binaries can differ by toolchain; they are not claimed byte-identical.
- Local version1.3.0/build6 was installed after backing up version1.2.0. Installed executable matches the locally verified package. The entire preference plist hash is unchanged, preserving the existing shortcut and configuration. One installed-provider read completed in0.807s with both windows available, outputting only availability/timing; one resident remains.

本机已更新为1.3.0/build6，旧版和偏好备份保留在本机私有临时目录。当前方案未自动切换；在“设置 → 胶囊 → 当前胶囊”选择 Codex · 5小时／每周，或使用菜单栏“选择胶囊”。两种方案显示剩余百分比、对应重置倒计时和官方白色徽标；约五分钟按需刷新。无登录、无对应窗口或读取失败显示—。

本轮仅运行相关检查，未再执行原生全套或性能矩阵。发布使用一次标签构建；随后的主分支交付文档提交标记 skip-ci，避免相同源码重复构建。真实额度与账户数据未进入仓库。公开下载包与本地包的哈希不同符合不同工具链预期。

## Package hashes

| Artifact | SHA-256 |
| --- | --- |
| Local installed executable | 75e9f71845d6a3f8eb15099130dd0cacd27a3e46947eade722d5a5888cf7637b |
| Local ZIP | 28c64c3d593a914a09fe8c67ba19775b47356c1638276154363bc141a002e71c |
| Public CI ZIP | b41827f7c217086cbd188ce8b58c98e4c27d040da9fa619e565ca30a552e1294 |

Public ZIP size:1,367,417bytes. New official mark/source attribution is in THIRD_PARTY_NOTICES.md. No new runtime/library is bundled; the optional quota feature requires an installed, signed-in Codex CLI. Intel/macOS13 hardware execution and Apple notarization were not performed. Existing native-build/Test framework/Intel compatibility-pack toolchain warnings are historical limitations, not a claim of new source errors.
