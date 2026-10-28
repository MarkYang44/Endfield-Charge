import AppKit
import ChargeCore

let arguments = CommandLine.arguments
if arguments.contains("--snapshot") {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do { print(String(decoding: try encoder.encode(BatteryReader.read()), as: UTF8.self)) }
    catch { fputs("\(error)\n", stderr); exit(1) }
    exit(0)
}

if arguments.contains("--telemetry-snapshot") {
    let reader = TelemetryReader()
    _ = reader.read(battery: BatteryReader.read(), powerEnabled: true, computeEnabled: true, thermalEnabled: true, networkEnabled: true, storageEnabled: true)
    Thread.sleep(forTimeInterval: 1)
    let value = reader.read(battery: BatteryReader.read(), powerEnabled: true, computeEnabled: true, thermalEnabled: true, networkEnabled: true, storageEnabled: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do { print(String(decoding: try encoder.encode(value), as: UTF8.self)) }
    catch { fputs("\(error)\n", stderr); exit(1) }
    exit(0)
}

// Read-only provider smoke; print availability metadata only, never account or quota values.
if arguments.contains("--codex-quota-check") {
    let started = ProcessInfo.processInfo.systemUptime
    let result = CodexQuotaRequest().read()
    print("Codex quota read: \(result == nil ? "unavailable" : "completed"); five-hour window: \(result?.fiveHour != nil); weekly window: \(result?.weekly != nil); seconds: \(String(format: "%.3f", ProcessInfo.processInfo.systemUptime - started))")
    exit(result == nil ? 1 : 0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
// Export modes use temporary preferences and never enter the resident lock/event loop.
func exportSettings() -> AppSettings {
    let domain = "com.markyang.endfieldcharge.export.\(UUID().uuidString)"
    let settings = AppSettings(defaults: UserDefaults(suiteName: domain)!)
    settings.value.language = arguments.contains("--zh") ? "zh" : "en"
    if arguments.contains("--disabled") {
        settings.value.powerTelemetryEnabled = false
        settings.value.computeTelemetryEnabled = false
        settings.value.thermalTelemetryEnabled = false
        settings.value.networkTelemetryEnabled = false
        settings.value.storageTelemetryEnabled = false
    }
    UserDefaults.standard.removePersistentDomain(forName: domain)
    return settings
}
func exportSnapshot(preferences: Preferences, demo: Bool) -> TelemetrySnapshot {
    func filtered(_ value: TelemetrySnapshot) -> TelemetrySnapshot {
        var result = value
        if !preferences.powerTelemetryEnabled { result.power = nil }
        if !preferences.computeTelemetryEnabled { result.compute = nil }
        if !preferences.thermalTelemetryEnabled { result.thermal = nil }
        if !preferences.networkTelemetryEnabled { result.network = nil }
        if !preferences.storageTelemetryEnabled { result.storage = nil }
        return result
    }
    if arguments.contains("--unavailable") {
        return TelemetrySnapshot(sampledAt: 100, battery: BatterySnapshot(hasBattery: false), power: nil, compute: nil, thermal: nil)
    }
    if demo {
        return filtered(TelemetrySnapshot(sampledAt: 100, battery: demoSnapshot(charging: true),
            power: PowerTelemetry(batteryWatts: 22.4, averageDischargeWatts: nil, adapterWatts: 70, cycleCount: 26),
            compute: ComputeTelemetry(cpuFraction: 0.37, memoryUsedBytes: 11 * 1_073_741_824,
                memoryTotalBytes: 24 * 1_073_741_824, compressedBytes: 2 * 1_073_741_824,
                swapUsedBytes: 1_073_741_824, pressure: .normal), thermal: .fair,
            network: NetworkTelemetry(downloadBytesPerSecond: 8.4 * 1_048_576, uploadBytesPerSecond: 1.2 * 1_048_576,
                receivedBytes: 3 * 1_073_741_824, sentBytes: 536_870_912, interfaces: ["en0", "en1"]),
            storage: StorageTelemetry(totalBytes: 512 * 1_073_741_824, freeBytes: 152 * 1_073_741_824,
                availableBytes: 140 * 1_073_741_824, path: "/System/Volumes/Data", fileSystem: "apfs")))
    }
    let reader = TelemetryReader()
    func read() -> TelemetrySnapshot {
        reader.read(battery: BatteryReader.read(), powerEnabled: preferences.powerTelemetryEnabled,
            computeEnabled: preferences.computeTelemetryEnabled, thermalEnabled: preferences.thermalTelemetryEnabled,
            networkEnabled: preferences.networkTelemetryEnabled, storageEnabled: preferences.storageTelemetryEnabled)
    }
    _ = read()
    Thread.sleep(forTimeInterval: 1)
    return read()
}
if let index = arguments.firstIndex(of: "--render-settings") {
    let tabs = ["general", "display", "alerts", "telemetry", "capsules", "rules", "about"]
    guard index + 1 < arguments.count else { fputs("Missing settings output path\n", stderr); exit(2) }
    var tab = 0
    if let i = arguments.firstIndex(of: "--tab") {
        guard i + 1 < arguments.count, let selected = tabs.firstIndex(of: arguments[i + 1]) else {
            fputs("Invalid settings tab\n", stderr); exit(2)
        }
        tab = selected
    }
    let settings = exportSettings()
    if arguments.contains("--demo") {
        var fixture = settings.value
        fixture.selectedCapsuleID = CapsuleProfile.networkID
        fixture.telemetryAlertRules = [TelemetryAlertRule(id: "demo.rule", name: "UPLOAD WATCH · DEMO", metric: .networkUploadBytesPerSecond,
            threshold: 2.5 * 1_048_576, holdSeconds: 10, cooldownSeconds: 120)]
        settings.applyFromPeer(fixture)
    }
    let controller = SettingsWindowController(settings: settings, selectedTab: tab, frame: nil,
        onPreview: { _ in }, onClose: { _, _ in })
    guard let content = controller.window?.contentView else { exit(1) }
    controller.window?.displayIfNeeded()
    if arguments.contains("--scroll-bottom") {
        func scroll(_ view: NSView) {
            if let scroller = view as? NSScrollView, let document = scroller.documentView {
                document.scroll(NSPoint(x: 0, y: document.bounds.height))
            }
            view.subviews.forEach(scroll)
        }
        scroll(content)
    }
    guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { exit(1) }
    content.cacheDisplay(in: content.bounds, to: bitmap)
    do {
        guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
        try png.write(to: URL(fileURLWithPath: arguments[index + 1]))
    } catch { fputs("Settings render failed: \(error)\n", stderr); exit(1) }
    exit(0)
}
if let index = arguments.firstIndex(of: "--render-telemetry") {
    guard index + 1 < arguments.count else {
        fputs("Usage: --render-telemetry /path/to/image.png --tab power|compute|thermal|network|storage [--demo] [--stage seconds] [--reduce-motion]\n", stderr); exit(2)
    }
    let tabs = ["power", "compute", "thermal", "network", "storage"]
    var tab = 0
    if let i = arguments.firstIndex(of: "--tab") {
        guard i + 1 < arguments.count, let selected = tabs.firstIndex(of: arguments[i + 1]) else {
            fputs("Invalid telemetry tab\n", stderr); exit(2)
        }
        tab = selected
    }
    var stage = arguments.contains("--reduce-motion") ? 0.15 : 2.52
    if let i = arguments.firstIndex(of: "--stage") {
        guard i + 1 < arguments.count, let seconds = Double(arguments[i + 1]), seconds.isFinite, seconds >= 0 else {
            fputs("Invalid render stage\n", stderr); exit(2)
        }
        stage = seconds
    }
    let settings = exportSettings()
    let view = TelemetryView(settings: settings, selectedTab: tab)
    view.header.reduceMotion = arguments.contains("--reduce-motion")
    let demo = arguments.contains("--demo")
    let snapshot = exportSnapshot(preferences: settings.value, demo: demo)
    if demo && !arguments.contains("--unavailable") {
        for i in 0..<24 {
            var point = snapshot
            point.sampledAt = 54 + Double(i * 2)
            point.network?.downloadBytesPerSecond = i == 10 ? nil : (4.2 + 4.2 * sin(Double(i) * 0.34)) * 1_048_576
            point.network?.uploadBytesPerSecond = i == 10 ? nil : (1.2 + 0.8 * sin(Double(i) * 0.6)) * 1_048_576
            view.update(point)
        }
    }
    view.update(snapshot)
    do { try view.renderPNG(at: URL(fileURLWithPath: arguments[index + 1]), seconds: stage, demo: demo) }
    catch { fputs("Telemetry render failed: \(error)\n", stderr); exit(1) }
    exit(0)
}
if let index = arguments.firstIndex(of: "--render") {
    guard index + 1 < arguments.count else { fputs("Usage: --render /path/to/image.png [--stage seconds] [--demo | --preview-unplug]\n", stderr); exit(2) }
    let settings = AppSettings()
    let view = HUDView(frame: NSRect(x: 0, y: 0, width: 620, height: 144))
    view.snapshot = arguments.contains("--demo") ? demoSnapshot(charging: true)
        : arguments.contains("--preview-unplug") ? demoSnapshot(charging: false) : BatteryReader.read()
    var renderPreferences = settings.value
    if arguments.contains("--capsule") && arguments.contains("--disabled") {
        renderPreferences.powerTelemetryEnabled = false
        renderPreferences.computeTelemetryEnabled = false
        renderPreferences.thermalTelemetryEnabled = false
        renderPreferences.networkTelemetryEnabled = false
        renderPreferences.storageTelemetryEnabled = false
    }
    view.preferences = renderPreferences
    view.chinese = arguments.contains("--capsule") && arguments.contains("--zh") ? true
        : arguments.contains("--capsule") && arguments.contains("--en") ? false : settings.chinese
    view.reduceMotion = arguments.contains("--reduce-motion")
    view.elapsed = 3.0
    if let stage = arguments.firstIndex(of: "--stage"), stage + 1 < arguments.count,
       let seconds = Double(arguments[stage + 1]) { view.elapsed = seconds }
    if let capsule = arguments.firstIndex(of: "--capsule") {
        guard capsule + 1 < arguments.count else { fputs("Missing capsule ID\n", stderr); exit(2) }
        let requested = arguments[capsule + 1]
        let id = settings.value.capsuleProfiles.contains(where: { $0.id == requested }) ? requested : "builtin." + requested
        let quotaMetric: TelemetryMetric? = requested == "codex-5h" ? .codexFiveHourRemainingPercent
            : requested == "codex-week" ? .codexWeeklyRemainingPercent : nil
        let fixtureProfile = quotaMetric.map { CapsuleProfile(id: "fixture.codex", title: $0 == .codexFiveHourRemainingPercent ? "CODEX 5H" : "CODEX WEEK", primaryMetric: $0, ringMetric: $0) }
        guard let profile = fixtureProfile ?? settings.value.capsuleProfiles.first(where: { $0.id == id }) else {
            fputs("Unknown capsule ID\n", stderr); exit(2)
        }
        if !profile.isDefaultBattery {
            var snapshot = exportSnapshot(preferences: renderPreferences, demo: arguments.contains("--demo"))
            if quotaMetric != nil {
                // Quota exports are synthetic and deterministic even when the host has a signed-in CLI.
                let now = 1_800_000_000.0
                view.quotaRenderTime = now
                snapshot.codexQuota = arguments.contains("--unavailable") ? nil : CodexQuotaSnapshot(
                    fiveHour: CodexQuotaWindow(usedPercent: 23, resetsAt: now + 2 * 3600 + 43 * 60),
                    weekly: CodexQuotaWindow(usedPercent: 42, resetsAt: now + 3 * 86400 + 5 * 3600))
            }
            if profile.isBatteryLayout { view.accentOverride = profile.resolvedAccent(in: snapshot) }
            else { view.capsule = CapsulePresentation(profile: profile, snapshot: snapshot) }
        }
    }
    do { try view.writePNG(to: URL(fileURLWithPath: arguments[index + 1])) }
    catch { fputs("Render failed: \(error)\n", stderr); exit(1) }
    exit(0)
}

// The settings role bypasses battery monitoring, status item and exclusive hotkey registration.
if let index = arguments.firstIndex(of: "--settings-ui") {
    guard index + 3 < arguments.count, let parent = Int32(arguments[index + 1]), let tab = Int(arguments[index + 2]) else {
        fputs("Invalid settings process arguments\n", stderr); exit(2)
    }
    let delegate = SettingsApplicationDelegate(parentPID: parent, tab: tab, frame: arguments[index + 3])
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
} else if let index = arguments.firstIndex(of: "--telemetry-ui") {
    guard index + 3 < arguments.count, let parent = Int32(arguments[index + 1]), let tab = Int(arguments[index + 2]) else {
        fputs("Invalid telemetry process arguments\n", stderr); exit(2)
    }
    let delegate = TelemetryApplicationDelegate(parentPID: parent, tab: tab, frame: arguments[index + 3])
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
} else {
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
