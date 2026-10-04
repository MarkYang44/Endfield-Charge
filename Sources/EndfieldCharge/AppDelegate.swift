import AppKit
import SwiftUI
import ChargeCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = AppSettings()
    private let monitor = PowerMonitor()
    private let hotkey = HotKey()
    private var hud: HUDController!
    private var status: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var reducer = PowerEventReducer()
    private var snapshot = BatterySnapshot(hasBattery: false)
    private var shortcutConfiguration = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep one resident agent; command-line rendering bypasses this delegate.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "com.markyang.endfieldcharge")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let other = others.first {
            other.activate(options: [])
            NSApplication.shared.terminate(nil)
            return
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        hud = HUDController(settings: settings)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = statusImage()
        status.button?.imagePosition = .imageLeading
        hotkey.onPress = { [weak self] in self?.preview() }
        settings.onChange = { [weak self] in self?.applySettings() }
        monitor.onSnapshot = { [weak self] in self?.receive($0) }
        monitor.start()
        applySettings()
        let arguments = CommandLine.arguments
        if arguments.contains("--demo") { chargingDemo() }
        else if arguments.contains("--preview-unplug") { batteryDemo() }
        else if arguments.contains("--preview") { preview() }
        else if arguments.contains("--settings") { openSettings() }
    }

    private func statusImage() -> NSImage {
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            return image
        }
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            NSColor.black.setFill()
            HUDView.boltPath(in: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func receive(_ value: BatterySnapshot) {
        snapshot = value
        updateMenu()
        for event in reducer.consume(value, lowThreshold: settings.value.lowThreshold) {
            switch event {
            case .connected, .disconnected: hud.show(value)
            case .lowBattery where settings.value.lowBatteryAlert: hud.show(value, kind: .lowBattery, queued: true)
            case .fullyCharged where settings.value.fullBatteryAlert: hud.show(value, kind: .fullyCharged, queued: true)
            case .lowPowerEnabled where settings.value.lowPowerAlert: hud.show(value, kind: .lowPowerEnabled, queued: true)
            case .lowPowerDisabled where settings.value.lowPowerAlert: hud.show(value, kind: .lowPowerDisabled, queued: true)
            default: break
            }
        }
    }

    private func applySettings() {
        let modifiers = settings.value.shortcutModifiers
        let configuration = "\(settings.value.shortcutEnabled):\(settings.value.shortcutKey):\(modifiers.map(\.rawValue).sorted())"
        if configuration != shortcutConfiguration {
            shortcutConfiguration = configuration
            let result = hotkey.configure(enabled: settings.value.shortcutEnabled, key: settings.value.shortcutKey, modifiers: modifiers)
            if settings.value.shortcutEnabled && modifiers.isDisjoint(with: [.command, .control, .option]) {
                settings.shortcutMessage = settings.text("请至少选择 Command、Control 或 Option。", "Choose at least Command, Control or Option.")
            } else {
                settings.shortcutMessage = result == 0 ? "" : settings.text(
                    "快捷键不可用，请换一个组合。", "This shortcut is unavailable. Choose another combination.")
            }
        }
        updateMenu()
        hud.position()
    }

    private func updateMenu() {
        status.button?.title = settings.value.showPercentage ? " " + (snapshot.percent.map { "\($0)%" } ?? "—") : ""
        status.button?.toolTip = settings.text("终末地电量终端", "Endfield Charge")
        let menu = NSMenu()
        menu.delegate = self
        let state: String
        if !snapshot.hasBattery { state = settings.text("未检测到内置电池", "No internal battery") }
        else if snapshot.isCharged { state = settings.text("已充满", "Fully charged") }
        else if snapshot.isCharging { state = settings.text("正在充电", "Charging") }
        else if snapshot.externalPower { state = settings.text("外部供电 · 未充电", "External power · Not charging") }
        else { state = settings.text("电池供电", "Battery power") }
        menu.addItem(NSMenuItem(title: "ENDFIELD / \(state)", action: nil, keyEquivalent: ""))
        if let minutes = snapshot.minutesRemaining, minutes > 0 {
            let suffix = snapshot.isCharging ? settings.text("至充满", "until full") : settings.text("剩余", "remaining")
            menu.addItem(NSMenuItem(title: "\(minutes / 60)h \(minutes % 60)m \(suffix)", action: nil, keyEquivalent: ""))
        }
        menu.addItem(.separator())
        item(settings.text("预览本机电量", "Preview Battery"), #selector(preview), in: menu)
        item(settings.text("模拟插电动画", "Charging Demo"), #selector(chargingDemo), in: menu)
        item(settings.text("模拟拔电动画", "Battery Demo"), #selector(batteryDemo), in: menu)
        menu.addItem(.separator())
        item(settings.text("设置…", "Settings…"), #selector(openSettings), in: menu, key: ",")
        item(settings.text("GitHub 仓库", "GitHub Repository"), #selector(openRepository), in: menu)
        menu.addItem(.separator())
        item(settings.text("退出 Endfield Charge", "Quit Endfield Charge"), #selector(quit), in: menu, key: "q")
        status.menu = menu
    }

    private func item(_ title: String, _ action: Selector, in menu: NSMenu, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    func menuWillOpen(_ menu: NSMenu) { monitor.scheduleRefresh() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        preview(); return false
    }

    @objc private func preview() { hud.show(BatteryReader.read()) }
    @objc private func chargingDemo() { hud.show(demoSnapshot(charging: true)) }
    @objc private func batteryDemo() { hud.show(demoSnapshot(charging: false)) }
    @objc private func openRepository() {
        NSWorkspace.shared.open(URL(string: "https://github.com/MarkYang44/Endfield-Charge")!)
    }
    @objc private func quit() { NSApplication.shared.terminate(nil) }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingView(rootView: SettingsView(settings: settings) { [weak self] charging in
                if let charging { self?.hud.show(demoSnapshot(charging: charging)) }
                else { self?.preview() }
            })
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 480),
                styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Endfield Charge · " + settings.text("设置", "Settings")
            window.contentView = hosting
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settings.refreshLogin()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

func demoSnapshot(charging: Bool) -> BatterySnapshot {
    BatterySnapshot(hasBattery: true, percent: 76, externalPower: charging, isCharging: charging,
        currentMAh: 3800, fullMAh: 5000, voltageMV: 12000, minutesRemaining: charging ? 45 : 240)
}
