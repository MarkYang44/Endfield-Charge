import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    var onPreview: (Bool?) -> Void
    private let accent = Color(NSColor(rgb: 0xC6CA4C))
    private func t(_ zh: String, _ en: String) -> String { settings.text(zh, en) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "bolt.fill").font(.system(size: 26)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("ENDFIELD CHARGE").font(.system(size: 17, weight: .bold, design: .monospaced)).tracking(2)
                    Text("/// MACOS POWER TERMINAL").font(.system(size: 9, design: .monospaced)).tracking(1.5).foregroundStyle(.secondary)
                }
                Spacer()
                Text("01 / POWER").font(.system(size: 10, design: .monospaced)).foregroundStyle(accent)
            }.padding(24)
            Divider()
            TabView {
                general.tabItem { Label(t("通用", "General"), systemImage: "slider.horizontal.3") }
                animation.tabItem { Label(t("显示与动画", "HUD & Animation"), systemImage: "waveform.path") }
                alerts.tabItem { Label(t("提醒", "Alerts"), systemImage: "bell") }
                about.tabItem { Label(t("关于", "About"), systemImage: "info.circle") }
            }.padding(16)
            Divider()
            HStack {
                Text(t("设置自动保存并即时生效", "Changes save automatically")).font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button(t("预览本机电量", "Preview Battery")) { onPreview(nil) }
            }.padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(width: 620, height: 480)
        .preferredColorScheme(.dark)
        .background(Color(NSColor(rgb: 0x262425)))
        .onAppear { settings.refreshLogin() }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 18) {
            row(t("语言", "Language")) {
                Picker("", selection: $settings.value.language) {
                    Text(t("跟随系统", "System")).tag("system")
                    Text("简体中文").tag("zh")
                    Text("English").tag("en")
                }.labelsHidden().frame(width: 180)
            }
            Toggle(t("菜单栏显示百分比", "Show percentage in menu bar"), isOn: $settings.value.showPercentage)
            Toggle(t("全局快捷键", "Global shortcut"), isOn: $settings.value.shortcutEnabled)
            row(t("快捷键组合", "Shortcut")) {
                Text("⌃ Control + ⌥ Option +").foregroundStyle(.secondary)
                Picker("", selection: $settings.value.shortcutKey) {
                    ForEach(["H", "B", "E", "P"], id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 70).disabled(!settings.value.shortcutEnabled)
            }
            if !settings.shortcutMessage.isEmpty { Text(settings.shortcutMessage).font(.caption).foregroundStyle(.orange) }
            Divider()
            Toggle(t("登录时启动", "Launch at login"), isOn: Binding(
                get: { settings.loginEnabled }, set: { settings.setLogin($0) }
            ))
            Text(t("建议先将应用放入 Applications，再启用登录启动。", "Move the app to Applications before enabling launch at login."))
                .font(.caption).foregroundStyle(.secondary)
            if !settings.loginMessage.isEmpty { Text(settings.loginMessage).font(.caption).foregroundStyle(.orange) }
            Spacer(minLength: 0)
        }.padding(16)
    }

    private var animation: some View {
        VStack(alignment: .leading, spacing: 17) {
            row(t("显示器", "Display")) {
                Picker("", selection: $settings.value.displayID) {
                    Text(t("当前主显示器", "Current main display")).tag(UInt32(0))
                    ForEach(Array(NSScreen.screens.enumerated()), id: \.element.screenNumber) { index, screen in
                        Text("\(index + 1). \(screen.localizedName)").tag(screenID(screen))
                    }
                }.labelsHidden().frame(width: 235)
            }
            row(t("顶部位置", "Top position")) {
                Picker("", selection: $settings.value.position) {
                    Text(t("靠左", "Left")).tag("left")
                    Text(t("居中", "Center")).tag("center")
                    Text(t("靠右", "Right")).tag("right")
                }.pickerStyle(.segmented).frame(width: 235)
            }
            row(t("全局缩放", "Scale")) {
                Slider(value: $settings.value.scale, in: 0.4...1.2, step: 0.05).frame(width: 190)
                Text(String(format: "%.0f%%", settings.value.scale * 100)).monospacedDigit().frame(width: 42)
            }
            row(t("总显示时长", "Total duration")) {
                Slider(value: $settings.value.duration, in: 3...10, step: 0.5).frame(width: 190)
                Text(String(format: "%.1fs", settings.value.duration)).monospacedDigit().frame(width: 42)
            }
            Toggle(t("启用能量波纹", "Energy ripples"), isOn: $settings.value.ripplesEnabled)
            Text(t("系统开启“减少动态效果”时，自动使用简化淡入淡出。", "Uses a gentle fade when Reduce Motion is enabled in macOS."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(t("模拟插电", "Charging Demo")) { onPreview(true) }
                Button(t("模拟拔电", "Battery Demo")) { onPreview(false) }
                Spacer()
            }
            Spacer(minLength: 0)
        }.padding(16)
    }

    private var alerts: some View {
        VStack(alignment: .leading, spacing: 22) {
            Toggle(t("低电量提醒", "Low battery alert"), isOn: $settings.value.lowBatteryAlert)
            row(t("低电量阈值", "Low battery threshold")) {
                Slider(value: Binding(get: { Double(settings.value.lowThreshold) },
                    set: { settings.value.lowThreshold = Int($0) }), in: 5...40, step: 1).frame(width: 190)
                Text("\(settings.value.lowThreshold)%").monospacedDigit().frame(width: 42)
            }
            Toggle(t("充满提醒", "Full charge alert"), isOn: $settings.value.fullBatteryAlert)
            Toggle(t("低电量模式切换提醒", "Low Power Mode changes"), isOn: $settings.value.lowPowerAlert)
            Text(t("提醒使用同风格 HUD。首次启动只读取状态，不重复弹出历史提醒。", "Alerts use the same HUD. Starting the app does not replay old alerts."))
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }.padding(16)
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Endfield Charge 1.0.0").font(.title2.bold())
            Text(t("终末地风格的 macOS 原生电量终端", "A native Endfield-inspired macOS battery HUD"))
            Text(t("视觉、图案和动画参考 QinAnze/zmd-charge。原生实现：Mark Yang。", "Visuals, geometry and timing inspired by QinAnze/zmd-charge. Native implementation: Mark Yang."))
                .font(.caption).foregroundStyle(.secondary)
            Text(t("“超充模式”为主题文案，不代表检测到快充。Wh 为根据当前电压推算的近似能量。", "“Super charge” is theme copy, not fast-charge detection. Wh is an estimate using the current voltage."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Link(t("GitHub 仓库", "GitHub Repository"), destination: URL(string: "https://github.com/MarkYang44/Endfield-Charge")!)
                Link(t("原项目", "Original Project"), destination: URL(string: "https://github.com/QinAnze/zmd-charge")!)
            }
            Spacer(minLength: 0)
            Text("/// INDUSTRIAL SYSTEM · LOCAL POWER TELEMETRY").font(.system(size: 9, design: .monospaced)).foregroundStyle(accent)
        }.padding(16)
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack { Text(title); Spacer(); content() }
    }
}

private extension NSScreen {
    var screenNumber: UInt32 { screenID(self) }
}
