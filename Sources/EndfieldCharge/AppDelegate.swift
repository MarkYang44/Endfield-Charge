import AppKit
import ChargeCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var resident: ResidentInstance?
    private let settings = AppSettings()
    private let monitor = PowerMonitor()
    private let hotkey = HotKey()
    private var hud: HUDController!
    private var menu: StatusMenuController!
    private var settingsProcess: SettingsProcessController!
    private var telemetryProcess: SettingsProcessController!
    private var telemetryMonitor: TelemetryMonitor!
    private var reducer = PowerEventReducer()
    private var snapshot = BatterySnapshot(hasBattery: false)
    private var shortcutConfiguration = ""
    private var shortcutStatus: Int32 = 0
    private var requestObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do { resident = try ResidentInstance() }
        catch ResidentInstance.LockError.alreadyRunning(let pid) {
            ResidentRequest.action(arguments: CommandLine.arguments).send(to: pid)
            NSApplication.shared.terminate(nil)
            return
        } catch {
            NSAlert(error: error).runModal()
            NSApplication.shared.terminate(nil)
            return
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        hud = HUDController(settings: settings)
        settingsProcess = SettingsProcessController(settings: settings, onPreview: { [weak self] charging in
            if let charging { self?.hud.show(demoSnapshot(charging: charging)) }
            else { self?.preview() }
        }, onScreen: { [weak self] display in
            self?.hud.contextDisplayID = display
            if display != nil { self?.hud.position() }
        })
        telemetryProcess = SettingsProcessController(settings: settings, role: .telemetry, onPreview: { [weak self] _ in
            self?.preview()
        }, onScreen: { [weak self] display in
            self?.hud.contextDisplayID = display
            if display != nil { self?.hud.position() }
        })
        telemetryMonitor = TelemetryMonitor(settings: settings, battery: { [weak self] in
            self?.snapshot ?? BatterySnapshot(hasBattery: false)
        })
        telemetryMonitor.onSnapshot = { [weak self] in self?.telemetryProcess.sendTelemetry($0) }
        telemetryMonitor.onThermalAlert = { [weak self] level in
            guard let self else { return }
            self.hud.show(self.snapshot, kind: level == .critical ? .thermalCritical : .thermalWarning, queued: true)
        }
        telemetryProcess.onVisibility = { [weak self] in self?.telemetryMonitor.setPanelVisible($0) }
        menu = StatusMenuController(settings: settings, target: self, entries: [
            ("", "", nil, ""),
            ("预览本机电量", "Preview Battery", #selector(preview), ""),
            ("模拟插电动画", "Charging Demo", #selector(chargingDemo), ""),
            ("模拟拔电动画", "Battery Demo", #selector(batteryDemo), ""),
            ("", "", nil, ""),
            ("设置…", "Settings…", #selector(openSettings), ","),
            ("遥测终端…", "Telemetry Terminal…", #selector(openTelemetry), ""),
            ("GitHub 仓库", "GitHub Repository", #selector(openRepository), ""),
            ("", "", nil, ""),
            ("退出 Endfield Charge", "Quit Endfield Charge", #selector(quit), "q")
        ])
        menu.onRefresh = { [weak self] in self?.monitor.scheduleRefresh() }
        hotkey.onPress = { [weak self] in self?.preview() }
        settings.onChange = { [weak self] in self?.applySettings() }
        monitor.onSnapshot = { [weak self] in self?.receive($0) }
        monitor.start()
        telemetryMonitor.start()
        applySettings()
        requestObserver = DistributedNotificationCenter.default().addObserver(forName: ResidentRequest.name,
            object: String(ProcessInfo.processInfo.processIdentifier), queue: .main) { [weak self] notification in
                guard let raw = notification.userInfo?["action"] as? String,
                      let request = ResidentRequest(rawValue: raw), let self else { return }
                switch request {
                case .preview: self.preview()
                case .settings: self.openSettings()
                case .telemetry: self.openTelemetry()
                case .chargeDemo: self.chargingDemo()
                case .batteryDemo: self.batteryDemo()
                }
        }
        let arguments = CommandLine.arguments
        if arguments.contains("--demo") { chargingDemo() }
        else if arguments.contains("--preview-unplug") { batteryDemo() }
        else if arguments.contains("--preview") { preview() }
        else if arguments.contains("--settings") { openSettings() }
        else if arguments.contains("--telemetry") { openTelemetry() }
    }

    private func receive(_ value: BatterySnapshot) {
        snapshot = value
        menu.update(snapshot)
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
            shortcutStatus = hotkey.configure(enabled: settings.value.shortcutEnabled, key: settings.value.shortcutKey, modifiers: modifiers)
        }
        if settings.value.shortcutEnabled && modifiers.isDisjoint(with: [.command, .control, .option]) {
            settings.shortcutMessage = settings.text("请至少选择 Command、Control 或 Option。", "Choose at least Command, Control or Option.")
        } else {
            settings.shortcutMessage = shortcutStatus == 0 ? "" : settings.text(
                "快捷键不可用，请换一个组合。", "This shortcut is unavailable. Choose another combination.")
        }
        menu.update(snapshot)
        hud.position()
        telemetryMonitor.preferencesChanged()
    }

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

    @objc private func openSettings() { settingsProcess.open() }
    @objc private func openTelemetry() { telemetryProcess.open() }
    func applicationWillTerminate(_ notification: Notification) {
        telemetryMonitor?.stop(); settingsProcess?.stop(); telemetryProcess?.stop()
        if let requestObserver { DistributedNotificationCenter.default().removeObserver(requestObserver) }
    }
}

func demoSnapshot(charging: Bool) -> BatterySnapshot {
    BatterySnapshot(hasBattery: true, percent: 76, externalPower: charging, isCharging: charging,
        currentMAh: 3800, fullMAh: 5000, voltageMV: 12000, minutesRemaining: charging ? 45 : 240)
}
