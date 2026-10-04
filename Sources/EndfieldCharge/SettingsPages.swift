import AppKit
import ChargeCore

extension SettingsWindowController {
    func generalPage(_ page: NSView) {
        popup(t("语言", "Language"), choices: [(t("跟随系统", "System"), "system"), ("简体中文", "zh"), ("English", "en")],
              key: \.language, in: page, y: 0, width: 180)
        toggle(t("菜单栏显示百分比", "Show percentage in menu bar"), \.showPercentage, in: page, y: 39)
        toggle(t("全局快捷键", "Global shortcut"), \.shortcutEnabled, in: page, y: 73)
        place(label(t("快捷键组合", "Shortcut")), in: page, y: 113, width: 200)
        for (index, modifier) in ShortcutModifier.allCases.enumerated() {
            let control = button(modifier.symbol, in: page, x: 318 + CGFloat(index) * 37, y: 108, width: 34) { c, sender in
                if (sender as! NSButton).state == .on { c.settings.value.shortcutModifiers.insert(modifier) }
                else { c.settings.value.shortcutModifiers.remove(modifier) }
            }
            control.setButtonType(.pushOnPushOff)
            control.toolTip = modifier.rawValue.capitalized
            control.setAccessibilityLabel(modifier.rawValue.capitalized)
            bindings.append { c in
                control.state = c.settings.value.shortcutModifiers.contains(modifier) ? .on : .off
                control.contentTintColor = control.state == .on ? c.accent : .secondaryLabelColor
                control.bezelColor = control.state == .on ? c.accent : nil
                control.isEnabled = c.settings.value.shortcutEnabled
            }
        }
        place(label("+"), in: page, x: 470, y: 113, width: 20)
        let letter = NSPopUpButton(frame: .zero, pullsDown: false)
        letter.addItems(withTitles: HotKey.availableKeys)
        place(letter, in: page, x: 502, y: 108, width: 70, height: 28)
        letter.setAccessibilityLabel(t("快捷键字母", "Shortcut letter"))
        bind(letter) { c, sender in c.settings.value.shortcutKey = (sender as! NSPopUpButton).titleOfSelectedItem ?? "H" }
        bindings.append { c in letter.selectItem(withTitle: c.settings.value.shortcutKey); letter.isEnabled = c.settings.value.shortcutEnabled }
        let shortcutMessage = caption("", in: page, y: 143, warning: true)
        bindings.append { c in shortcutMessage.stringValue = c.settings.shortcutMessage }
        separator(in: page, y: 180)
        let login = NSButton(checkboxWithTitle: t("登录时启动", "Launch at login"), target: nil, action: nil)
        place(login, in: page, y: 196, width: 572)
        bind(login) { c, sender in c.settings.setLogin((sender as! NSButton).state == .on) }
        bindings.append { c in login.state = c.settings.loginEnabled ? .on : .off }
        _ = caption(t("建议先将应用放入 Applications，再启用登录启动。", "Move the app to Applications before enabling launch at login."), in: page, y: 235)
        let loginMessage = caption("", in: page, y: 271, warning: true)
        bindings.append { c in loginMessage.stringValue = c.settings.loginMessage }
    }

    func animationPage(_ page: NSView) {
        place(label(t("显示器", "Display")), in: page, y: 4, width: 200)
        let display = NSPopUpButton(frame: .zero, pullsDown: false)
        display.addItem(withTitle: t("当前主显示器", "Current main display"))
        display.lastItem?.representedObject = UInt32(0)
        for (index, screen) in NSScreen.screens.enumerated() {
            display.addItem(withTitle: "\(index + 1). \(screen.localizedName)")
            display.lastItem?.representedObject = screenID(screen)
        }
        place(display, in: page, x: 337, y: 0, width: 235, height: 28)
        display.setAccessibilityLabel(t("显示器", "Display"))
        bind(display) { c, sender in
            if let id = (sender as! NSPopUpButton).selectedItem?.representedObject as? UInt32 { c.settings.value.displayID = id }
        }
        bindings.append { c in
            display.select(display.itemArray.first { $0.representedObject as? UInt32 == c.settings.value.displayID } ?? display.item(at: 0))
        }
        place(label(t("顶部位置", "Top position")), in: page, y: 44, width: 200)
        let positions = ["left", "center", "right"]
        let position = NSSegmentedControl(labels: [t("靠左", "Left"), t("居中", "Center"), t("靠右", "Right")], trackingMode: .selectOne, target: nil, action: nil)
        place(position, in: page, x: 337, y: 40, width: 235, height: 28)
        position.setAccessibilityLabel(t("顶部位置", "Top position"))
        bind(position) { c, sender in
            let index = (sender as! NSSegmentedControl).selectedSegment
            if positions.indices.contains(index) { c.settings.value.position = positions[index] }
        }
        bindings.append { c in position.selectedSegment = positions.firstIndex(of: c.settings.value.position) ?? 1 }
        slider(t("全局缩放", "Scale"), in: page, y: 80, range: 0.4...1.2, step: 0.05,
               value: { $0.scale }, set: { $0.scale = $1 }, format: { String(format: "%.0f%%", $0 * 100) })
        slider(t("总显示时长", "Total duration"), in: page, y: 120, range: 3...10, step: 0.5,
               value: { $0.duration }, set: { $0.duration = $1 }, format: { String(format: "%.1fs", $0) })
        toggle(t("启用能量波纹", "Energy ripples"), \.ripplesEnabled, in: page, y: 164)
        _ = caption(t("系统开启“减少动态效果”时，自动使用简化淡入淡出。", "Uses a gentle fade when Reduce Motion is enabled in macOS."), in: page, y: 201)
        button(t("模拟插电", "Charging Demo"), in: page, y: 249) { c, _ in c.onPreview(true) }
        button(t("模拟拔电", "Battery Demo"), in: page, x: 150, y: 249) { c, _ in c.onPreview(false) }
    }

    func alertsPage(_ page: NSView) {
        toggle(t("低电量提醒", "Low battery alert"), \.lowBatteryAlert, in: page, y: 0)
        slider(t("低电量阈值", "Low battery threshold"), in: page, y: 46, range: 5...40, step: 1,
               value: { Double($0.lowThreshold) }, set: { $0.lowThreshold = Int($1) }, format: { "\(Int($0))%" })
        toggle(t("充满提醒", "Full charge alert"), \.fullBatteryAlert, in: page, y: 96)
        toggle(t("低电量模式切换提醒", "Low Power Mode changes"), \.lowPowerAlert, in: page, y: 143)
        _ = caption(t("提醒使用同风格 HUD。首次启动只读取状态，不重复弹出历史提醒。", "Alerts use the same HUD. Starting the app does not replay old alerts."), in: page, y: 195)
    }

    func telemetryPage(_ page: NSView) {
        toggle(t("电源遥测", "Power telemetry"), \.powerTelemetryEnabled, in: page, y: 0)
        toggle(t("CPU 与内存遥测", "CPU and memory telemetry"), \.computeTelemetryEnabled, in: page, y: 42)
        toggle(t("系统散热状态", "System thermal state"), \.thermalTelemetryEnabled, in: page, y: 84)
        toggle(t("散热压力提醒", "Thermal pressure alerts"), \.thermalAlert, in: page, y: 126)
        _ = caption(t("从菜单栏打开「遥测终端」。窗口打开时每 2 秒采样，后台每 30 秒。", "Open Telemetry Terminal from the menu. Samples every 2 s while open, 30 s in the background."), in: page, y: 174)
        _ = caption(t("关闭模块会停止额外采集。功率、内存为估算；散热状态不是温度读数。", "Disabled modules stop collection. Power and memory are estimates; thermal state is not a temperature."), in: page, y: 226)
    }

    func aboutPage(_ page: NSView) {
        place(label("Endfield Charge 1.0.0", size: 21, weight: .bold), in: page, y: 0, width: 572, height: 30)
        place(label(t("终末地风格的 macOS 原生电量终端", "A native Endfield-inspired macOS battery HUD")), in: page, y: 46, width: 572)
        _ = caption(t("视觉、图案和动画参考 QinAnze/zmd-charge。原生实现：Mark Yang。", "Visuals, geometry and timing inspired by QinAnze/zmd-charge. Native implementation: Mark Yang."), in: page, y: 85)
        _ = caption(t("“超充模式”为主题文案，不代表检测到快充。Wh 为根据当前电压推算的近似能量。", "“Super charge” is theme copy, not fast-charge detection. Wh is approximate energy based on the current voltage."), in: page, y: 128)
        button("GitHub / Endfield-Charge", in: page, y: 176, width: 220) { _, _ in
            NSWorkspace.shared.open(URL(string: "https://github.com/MarkYang44/Endfield-Charge")!)
        }
        button(t("原项目 / zmd-charge", "Original / zmd-charge"), in: page, x: 240, y: 176, width: 210) { _, _ in
            NSWorkspace.shared.open(URL(string: "https://github.com/QinAnze/zmd-charge")!)
        }
        let footer = label("ENDFIELD INDUSTRIES // POWER MANAGEMENT TERMINAL", size: 9, mono: true)
        footer.textColor = .secondaryLabelColor
        place(footer, in: page, y: 256, width: 572)
    }
}
