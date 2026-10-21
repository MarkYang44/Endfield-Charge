[English](DEVELOPMENT.md) | 简体中文

# 开发指南

需要 Swift 6 工具链，安装 Xcode 或 Apple Command Line Tools 即可；无第三方包依赖。应用部署目标是 macOS 13；测试使用 Swift Testing，建议在 macOS 14+ 运行。

```bash
git clone https://github.com/MarkYang44/Endfield-Charge.git
cd Endfield-Charge
bash scripts/test.sh
bash scripts/build-app.sh --universal
open "dist/Endfield Charge.app"
```

只编译本机架构可以省略 `--universal`。产物：`dist/Endfield Charge.app` 和 `dist/Endfield-Charge-macOS.zip`。`scripts/test.sh` 包含 Command Line Tools 环境下 Swift Testing 的 framework 路径适配。

在有图形桌面的本机可额外运行 `bash scripts/check-runtime.sh`，检查原生窗口释放、消息传输、快速重开和提醒排队。它使用独立测试偏好域，不修改已安装应用的设置；CI 只运行不依赖桌面的核心测试。

```bash
"dist/Endfield Charge.app/Contents/MacOS/EndfieldCharge" --snapshot
open "dist/Endfield Charge.app" --args --preview
open "dist/Endfield Charge.app" --args --demo
open "dist/Endfield Charge.app" --args --preview-unplug
open "dist/Endfield Charge.app" --args --settings
"dist/Endfield Charge.app/Contents/MacOS/EndfieldCharge" --telemetry
"dist/Endfield Charge.app/Contents/MacOS/EndfieldCharge" --telemetry-snapshot
"dist/Endfield Charge.app/Contents/MacOS/EndfieldCharge" --render-telemetry /tmp/terminal.png --tab compute --demo
"dist/Endfield Charge.app/Contents/MacOS/EndfieldCharge" --render /tmp/hud.png --demo --stage 1.55
"dist/Endfield Charge.app/Contents/MacOS/EndfieldCharge" --render /tmp/network-hud.png --capsule network --demo
"dist/Endfield Charge.app/Contents/MacOS/EndfieldCharge" --render-settings /tmp/rules.png --tab rules --demo --zh
```

`--snapshot` 输出实际电池 JSON；`--telemetry-snapshot` 在间隔 1 秒的两次采集后输出实际遥测 JSON。`--render-telemetry` 支持 `--tab power|compute|thermal|network|storage`、`--stage seconds` 和 `--reduce-motion`；`--demo` 会在图中明确标注演示数据。`--render --capsule` 支持现有方案 ID 或 `battery|cpu|memory|network|storage` 预设名。`--render-settings` 支持 `general|display|alerts|telemetry|capsules|rules|about`，导出真实 AppKit 内容视图（不含系统标题栏与工具栏），`--zh` 可切换中文。导出 PNG 和读取 JSON 不启动常驻进程。

直接调用可执行文件时，`--telemetry`、`--settings`、`--preview`、`--capsule-preview`、`--demo`、`--preview-unplug` 会将固定动作转发给已有常驻实例。macOS `open … --args` 在应用已经运行时不能可靠传递参数，此时用菜单栏或直接调用可执行文件；普通双击重开依然预览实际电量。

## 项目结构

```text
Sources/ChargeCore/          电池/遥测模型、差分、规则与方案、事件、动画时间线、偏好与通信
Sources/EndfieldCharge/      原生采集/监听、AppKit HUD与遥测、菜单栏、快捷键、界面进程生命周期
Tests/ChargeCoreTests/       电量、差分、规则、配置迁移和动画测试
Tests/RuntimeChecks/         需要图形桌面的原生生命周期与通信检查
Resources/                  新图标 PNG / SVG 与用户提供的原始标识
scripts/                    图标矢量导出、测试与 .app / zip 打包
.github/workflows/          通用架构 CI、标签 Release
docs/                       设计、执行计划、验证记录与预览图
```

图标的原生矢量源可重复导出：

```bash
swift scripts/render-icons.swift
```

推送 main 会测试并打包 universal zip；推送 `v*` 标签会创建 Release。尚未签发 Developer ID 或公证，CI 使用 ad-hoc 签名。


内存测量与历史结果见 [性能记录](PERFORMANCE.md)。

## 配置与通信边界

标题／规则名称最多 32 个字符且不超过 1,024 个 UTF-8 字节；ID 最多 64 个字符且不超过 256 字节，规范化保留完整字素。私有通信每帧负载上限为 128 KiB（不含换行），发送与接收采用同一限制；超大帧会丢弃至换行，随后恢复接收正常帧。正常中文及 32 个家庭 Emoji 名称均受支持。


## v1.2.0 配置验证

[配置指南](configuration-sharing.zh-CN.md)（[English](configuration-sharing.md)）说明分享范围、安全默认值和播放行为。分享校验严格且带版本；旧 Preferences 迁移保持宽容。常驻端 ConfigurationTransactionService 负责校验、原子备份及一次提交，辅助进程只发送请求并接收权威版本。撤销恢复一份完整快照，不修改 SMAppService 注册。CapsulePlaybackScheduler 使用确定性状态机；单个原生协调器管理 HUD 与截止计时，静态紧凑保持停止动画计时器。

先用 `bash scripts/test.sh` 构建 ChargeCore，再运行 `bash scripts/check-runtime.sh` 检查真实控件、管道及子进程，包括扩展 UTF-8 极值配置。隔离导出演示界面：

```bash
ENDFIELD_EDITORS_ONLY=1 ENDFIELD_EDITOR_SCREENSHOTS=/tmp/endfield-demo bash scripts/check-runtime.sh
```

此命令使用临时偏好导出真实中英文设置及生产配色／散热／内存压力 HUD，不使用用户读数。`ENDFIELD_SHARING_ONLY=1` 可仅运行分享检查，其截图 fixture 见 Tests/RuntimeChecks/SharingChecks.swift。`--render-settings --scroll-bottom` 导出可滚动页底部。原电池回归使用 `--render /tmp/battery.png --demo --stage 1.55`、阶段 3，以及阶段 0.15 加 `--reduce-motion`；不要通过修改图案更新基准。

[分版本验证](capsule-sharing-validation.md)记录命令、物理占用汇总、安装包哈希与限制。真实偏好备份和原始遥测样本保留在仓库之外。性能脚本只用于开发，应用不打包 Python、.NET、字体或其他运行时。
