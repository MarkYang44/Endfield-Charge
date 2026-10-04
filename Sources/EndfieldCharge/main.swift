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
    _ = reader.read(battery: BatteryReader.read(), powerEnabled: true, computeEnabled: true, thermalEnabled: true)
    Thread.sleep(forTimeInterval: 1)
    let value = reader.read(battery: BatteryReader.read(), powerEnabled: true, computeEnabled: true, thermalEnabled: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do { print(String(decoding: try encoder.encode(value), as: UTF8.self)) }
    catch { fputs("\(error)\n", stderr); exit(1) }
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
if let index = arguments.firstIndex(of: "--render-telemetry") {
    guard index + 1 < arguments.count else {
        fputs("Usage: --render-telemetry /path/to/image.png --tab power|compute|thermal [--demo] [--stage seconds] [--reduce-motion]\n", stderr); exit(2)
    }
    let tabs = ["power", "compute", "thermal"]
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
    let settings = AppSettings()
    let view = TelemetryView(settings: settings, selectedTab: tab)
    view.header.reduceMotion = arguments.contains("--reduce-motion")
    let demo = arguments.contains("--demo")
    if demo {
        view.update(TelemetrySnapshot(sampledAt: 100, battery: demoSnapshot(charging: true),
            power: PowerTelemetry(batteryWatts: 22.4, averageDischargeWatts: nil, adapterWatts: 70, cycleCount: 26),
            compute: ComputeTelemetry(cpuFraction: 0.37, memoryUsedBytes: 11 * 1_073_741_824,
                memoryTotalBytes: 24 * 1_073_741_824, compressedBytes: 2 * 1_073_741_824,
                swapUsedBytes: 1_073_741_824, pressure: .normal), thermal: .fair))
    } else {
        let reader = TelemetryReader(), preferences = settings.value
        _ = reader.read(battery: BatteryReader.read(), powerEnabled: preferences.powerTelemetryEnabled,
            computeEnabled: preferences.computeTelemetryEnabled, thermalEnabled: preferences.thermalTelemetryEnabled)
        Thread.sleep(forTimeInterval: 1)
        view.update(reader.read(battery: BatteryReader.read(), powerEnabled: preferences.powerTelemetryEnabled,
            computeEnabled: preferences.computeTelemetryEnabled, thermalEnabled: preferences.thermalTelemetryEnabled))
    }
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
    view.preferences = settings.value
    view.chinese = settings.chinese
    view.reduceMotion = arguments.contains("--reduce-motion")
    view.elapsed = 3.0
    if let stage = arguments.firstIndex(of: "--stage"), stage + 1 < arguments.count,
       let seconds = Double(arguments[stage + 1]) { view.elapsed = seconds }
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
