# Endfield Charge · macOS 终末地风格电量 HUD

一个原生 Swift 菜单栏工具。插拔充电器时，从屏幕顶部弹出「电标 → 模式标题 → 电量胶囊」三段动画，视觉、图案、配色及节奏参考 [QinAnze/zmd-charge](https://github.com/QinAnze/zmd-charge)。

![超充模式](docs/images/charge-title.png)
![电池模式](docs/images/battery-title.png)
![电量胶囊](docs/images/battery-level.png)

## 使用

需要 macOS 13 或更新版本。应用支持 Apple Silicon 与 Intel；本地通过 `--universal` 打包可得到双架构版本。

下载 [GitHub Actions 构建产物](https://github.com/MarkYang44/Endfield-Charge/actions)或 [Releases](https://github.com/MarkYang44/Endfield-Charge/releases) 中的 zip，解压后把 **Endfield Charge.app** 放入 Applications，双击启动。菜单栏会出现电标和电量。点击图标可预览、模拟插拔电源、打开设置或退出。

默认全局快捷键 **Control + Option + H**，在设置中可关闭或改为 B / E / P。应用不需要辅助功能或录屏权限。默认关闭登录启动，移入 Applications 后可在设置中主动开启。

本地构建使用 ad-hoc 签名，尚未经过 Apple 公证。网络下载的副本可能需要通过 macOS 的“打开”或“隐私与安全性”流程确认。不要关闭 Gatekeeper。

## 功能

- 忠实保留 560×60 → 560×90 → 560×60 胶囊、双平行四边形电标、白色标题、黄绿色笔记本电量环；低于 20% 时电量环变红。
- 插电波纹向外扩散，拔电波纹向内收拢；HUD 不抢焦点、不挡鼠标，可见胶囊紧贴菜单栏和刘海下方（间距约 2 pt），展开时向下伸展。
- IOKit 电源事件监听、400ms 去抖、30 秒刷新兜底和唤醒后刷新。动画计时器仅在 HUD 展示时运行。
- 真实百分比、剩余时间和近似 Wh（一位小数）；正确区分接电未充电、正在充电、已充满及电池供电。
- 多显示器选择、顶部左/中/右、40–120% 缩放、3–10 秒时长、波纹开关、中文/英文/跟随系统、菜单栏百分比。
- 低电量、充满和系统低电量模式切换提醒，阈值可调；首次启动不会补发历史提醒。
- 跟随系统“减少动态效果”，使用简化淡入淡出。设置自动保存到应用的 UserDefaults 域。

“超充模式”沿用主题文案，**不代表实际检测到快充协议**。macOS IOPS 的容量通常是百分比，本项目不会把 100% 假装成 100mAh。Wh 只在系统另有原始物理容量和电压时推算，并以 **≈** 标注；这些 registry 字段并非稳定的公开接口，读不到时显示 `—`。根据当前电压估算的能量不能当作精确测量。充满提醒以系统已充满，或停止充电且 ≥99% 为准，并在重新消耗至 ≤95% 或拔电后重新允许提醒。

## 从源码构建

需要 Swift 6 工具链，安装 Xcode 或 Apple Command Line Tools 即可；无第三方包依赖。应用部署目标是 macOS 13；测试使用 Swift Testing，建议在 macOS 14+ 运行。

```bash
git clone https://github.com/MarkYang44/Endfield-Charge.git
cd Endfield-Charge
bash scripts/test.sh
bash scripts/build-app.sh --universal
open "dist/Endfield Charge.app"
```

只编译本机架构可以省略 `--universal`。产物：`dist/Endfield Charge.app` 和 `dist/Endfield-Charge-macOS.zip`。`scripts/test.sh` 包含 Command Line Tools 环境下 Swift Testing 的 framework 路径适配。

```bash
"dist/Endfield Charge.app/Contents/MacOS/EndfieldCharge" --snapshot
open "dist/Endfield Charge.app" --args --preview
open "dist/Endfield Charge.app" --args --demo
open "dist/Endfield Charge.app" --args --preview-unplug
open "dist/Endfield Charge.app" --args --settings
"dist/Endfield Charge.app/Contents/MacOS/EndfieldCharge" --render /tmp/hud.png --demo --stage 1.55
```

`--snapshot` 输出实际电池 JSON；`--demo` / `--preview-unplug` 使用演示数据，`--preview` 使用实际数据。已有实例运行时再次打开应用会预览实际电量；要使用启动参数中的模拟模式，请先退出旧实例。导出 PNG 和读取 JSON 不会启动常驻进程。

## 项目结构

```text
Sources/ChargeCore/          电池解析、电源事件、确定性动画时间线
Sources/EndfieldCharge/      AppKit HUD、IOKit 监听、菜单栏、快捷键、SwiftUI 设置
Tests/ChargeCoreTests/       电量、事件和动画测试
Resources/                  原项目应用图标
scripts/                    测试与 .app / zip 打包
.github/workflows/          通用架构 CI、标签 Release
docs/                       设计、执行计划、验证记录与预览图
```

推送 main 会测试并打包 universal zip；推送 `v*` 标签会创建 Release。尚未签发 Developer ID 或公证，CI 使用 ad-hoc 签名。

MIT。参考设计、图标与几何来源见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。这是非官方工具。
