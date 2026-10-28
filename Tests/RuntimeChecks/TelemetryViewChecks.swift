import AppKit
import ChargeCore

func runTelemetryViewChecks(settings: AppSettings) throws {
    let telemetryBytes = try JSONEncoder().encode(SettingsMessage(.telemetry, preferences: settings.value, telemetry: telemetrySample))
    check(telemetryBytes.count <= SettingsMessage.maximumPayloadBytes, "A telemetry IPC frame fits the private pipe bound")
    let decodedTelemetry = try JSONDecoder().decode(SettingsMessage.self, from: telemetryBytes)
    check(decodedTelemetry.telemetry == telemetrySample,
        "Typed telemetry survives the actual IPC encoder")
    for tab in 0..<5 {
        weak var releasedTerminal: TelemetryWindowController?
        weak var releasedView: TelemetryView?
        autoreleasepool {
            var terminal: TelemetryWindowController? = TelemetryWindowController(settings: settings, selectedTab: tab,
                frame: nil, onPreview: {}, onClose: { _, _ in })
            releasedTerminal = terminal; releasedView = terminal?.view
            terminal?.update(telemetrySample)
            terminal?.present()
            check(terminal?.selectedTab == tab && terminal?.view.header.snapshot.percent == 68, "Every telemetry page accepts actual data")
            if let view = terminal?.view, let tabs = view.subviews.compactMap({ $0 as? NSSegmentedControl }).first,
               let action = tabs.action {
                tabs.selectedSegment = (tab + 1) % 5
                app.sendAction(action, to: tabs.target, from: tabs)
                check(terminal?.selectedTab == (tab + 1) % 5, "Palette-rendered native page control still dispatches selection")
                terminal?.selectedTab = tab
            } else { check(false, "Native telemetry page selector exists") }
            spin(2.7)
            check(terminal?.view.headerTimerActive == false, "Original header timeline stops after settling")
            for i in 0..<400 {
                var sample = telemetrySample; sample.sampledAt = Double(i + 200)
                terminal?.update(sample)
            }
            check((terminal?.view.graphSampleCount ?? 301) <= 300, "Visible graph history is bounded")
            terminal?.window?.close(); terminal = nil
        }
        spin(0.1)
        check(releasedTerminal == nil && releasedView == nil, "Closed terminal releases view, history and animation owner")
    }
    print("PASS: five telemetry pages, bounded graph, stopped header timer and complete release")
    autoreleasepool {
        let view = TelemetryView(settings: settings)
        view.header.reduceMotion = true
        view.startHeaderAnimation()
        spin(0.25)
        check(!view.headerTimerActive && view.header.elapsed == 0.15, "Reduced Motion stops the header timer at its fade endpoint")
    }
}
