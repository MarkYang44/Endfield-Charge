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

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
if let index = arguments.firstIndex(of: "--render") {
    guard index + 1 < arguments.count else { fputs("Usage: --render /path/to/image.png [--stage seconds] [--demo | --preview-unplug]\n", stderr); exit(2) }
    let settings = AppSettings()
    let view = HUDView(frame: NSRect(x: 0, y: 0, width: 620, height: 144))
    view.snapshot = arguments.contains("--demo") ? demoSnapshot(charging: true)
        : arguments.contains("--preview-unplug") ? demoSnapshot(charging: false) : BatteryReader.read()
    view.preferences = settings.value
    view.chinese = settings.chinese
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
} else {
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
