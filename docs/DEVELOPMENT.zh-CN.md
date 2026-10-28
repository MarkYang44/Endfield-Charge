[English](DEVELOPMENT.md) | 简体中文

# 开发指南

需要 Swift 6 工具链，安装 Xcode 或 Apple Command Line Tools 即可；无第三方包依赖。应用部署目标是 macOS 13；测试使用 Swift Testing，建议在 macOS 14+ 运行。

```bash
bash scripts/verify.sh core --filter CapsulePlayback # 相关核心测试
bash scripts/verify.sh desktop hud                  # 相关原生组，先构建最新核心对象
bash scripts/verify.sh package                      # 只检查现有 dist，不重新构建
# 按需显式运行完整验证：
bash scripts/verify.sh core
bash scripts/verify.sh desktop all
bash scripts/verify.sh release # 完整 desktop + 通用构建 + 包检查
```

日常改动只选择受影响的检查，不重复无关全量回归。`scripts/test.sh` 将带引号的参数原样转发给 `swift test`，例如 `--filter 'CapsulePlayback|ConfigurationLimits'`。`scripts/check-runtime.sh --group all|hud|telemetry|sharing|editors|ipc` 先构建最新 ChargeCore 对象（不运行全量核心测试），再编译并执行所选原生组。`verify.sh desktop <group>` 同理；只有 `desktop all` 显式运行完整核心和原生检查；不带组名的 `desktop` 输出用法并失败。保留 `ENDFIELD_EDITORS_ONLY`、`ENDFIELD_SHARING_ONLY` 兼容入口。缺少组值、未知组和未知模式会在编译前输出用法并失败。

纯模型、限制、分享、调度器改动使用相关 `core --filter`；播放及渲染所有权选 `desktop hud`；原生遥测选 `telemetry`；控件选 `editors`；原生事务选 `sharing`；管道、窗口与子进程生命周期选 `ipc`。原生检查使用独立偏好域、真实窗口、管道、子进程及定时器，不改已安装应用的设置，也不能证明每种 Mac 的传感器精度。完整 `release` 是显式分发门槛，不是日常默认命令。

`bash scripts/build-app.sh --universal` 生成 `dist/Endfield Charge.app` 和 `dist/Endfield-Charge-macOS.zip`，省略 `--universal` 可只编译本机架构。`bash scripts/verify.sh package` 只验证现有产物的 arm64/x86_64、两种架构及 Info.plist 的 macOS 13.0 最低版本、预期资源、严格临时签名、ZIP 完整性，以及解压应用与构建应用一致。`check-package.sh` 也可同时传入应用和 ZIP 路径，用临时副本做负向测试；任意有效 ZIP 不能冒充应用分发包。包检查不等于公证或 Intel 硬件运行验证。

云端 CI 运行 `verify.sh core`、通用构建和包验证。原生检查只通过 `desktop-checks.yml` 手动触发，标签为 `[self-hosted, macOS, endfield-desktop]`，没有 PR/push 触发。手动选项默认 `hud`，只有选择 `all` 才额外运行全量核心测试。当前不假设已配置 runner；管理员需提供可信 Mac、上述工具链并注册标签，在已登录且可访问 WindowServer 的图形用户会话中启动 runner。只选择可信代码版本；无桌面的后台服务不够。工作流需由操作者单独触发。

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

验证性能时，在同一主机、编译器、预热和采样窗口下，对比 idle/settings/telemetry 场景的 physical footprint，重复测量并报告噪声；重构本身不保证更低内存。确定性渲染对比固定演示数据、语言、动画阶段和 Reduce Motion，保留原始素材哈希。
