# v1.3.1 delivery / 交付记录

Source/tag: `85f5ad7186be3c697775e3f1a86fc5b3c73ef171` / `v1.3.1`. [Release](https://github.com/MarkYang44/Endfield-Charge/releases/tag/v1.3.1) · [successful tag build](https://github.com/MarkYang44/Endfield-Charge/actions/runs/43755199251).

- `bash scripts/verify.sh release` passed locally: 122 core tests, all 26 native runtime groups (including the new interaction group, and the ipc telemetry child now driven by AppKit notifications instead of fixed timers), universal arm64/x86_64 build and package checks. Tag CI passed core tests, universal build and package validation before publishing.
- Battery title (stage 1.55), compact (stage 3) and Reduce Motion (stage 0.15) exports are byte-identical between the 1.3.0 source (`d85fb5c`) and this release on the same host. The committed `battery-title.png` predates the current macOS text rendering and was not regenerated.
- Interaction checks cover the hidden UI menu keys, footer status, section index, jump links, dependent threshold, top-left window restore, the menu shortcut hint and drag-and-drop import. The carousel swap never drops below 96 % scale and ends fully opaque.
- Settings screenshots in both READMEs and sharing guides were regenerated from the existing demo exports (`--render-settings`, `ENDFIELD_EDITOR_SCREENSHOTS`).
- Local version 1.3.0/build 6 was replaced in place by 1.3.1/build 7 after backing up the app and preferences. The installed executable matches the locally verified package, the exported preference domain is byte-identical before and after, the login item stays enabled and one resident runs.
- The public ZIP was not re-downloaded; its digest below comes from the GitHub release API. Local and CI binaries come from different toolchains and are not claimed byte-identical.

本版为交互打磨：设置与遥测窗口支持标准快捷键与分区切换；新增修饰键键帽、分区标识、底栏状态行、胶囊页底栏预览、页面互跳与拖入导入；轮播切换不再缩小到零。原电量 HUD 图案与三段动画逐字节不变，偏好格式未改。本地完整执行 `verify.sh release`（核心测试、26 组原生检查、通用构建与包检查），标签 CI 构建通过后发布。本机已在备份应用与偏好后原位更新为 1.3.1/build7：安装的可执行文件与本地验证包一致，偏好导出前后逐字节相同，登录项保持启用，仅一个常驻进程。未重新下载公开安装包。

## Package hashes

| Artifact | SHA-256 |
| --- | --- |
| Local executable | 3ce22e74f67eebb61568bafee23c2994efa3547f8ce209f0516500f37ae5f1b3 |
| Local ZIP | 6eff617e501eaf2451923484b7f6f5ac9a116e82b81d88373b3249bcafd8454c |
| Public CI ZIP | cd07cdf76fd8becfdc5522e9347e8c5a11291717fc25f5818727a0c32b3976f6 |

Public ZIP size: 1,396,170 bytes; local ZIP: 1,346,584 bytes. No new runtime or library is bundled. Intel/macOS 13 hardware execution and Apple notarization were not performed. The existing x86_64 compatibility-pack linker warning is a historical toolchain limitation, not a new source error.
