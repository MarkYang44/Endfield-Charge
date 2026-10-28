import AppKit
import ChargeCore

func runChildRoleIfRequested() {
    let telemetryRole = CommandLine.arguments.contains("--telemetry-ui")
    if let index = CommandLine.arguments.firstIndex(of: telemetryRole ? "--telemetry-ui" : "--settings-ui") {
        let args = CommandLine.arguments
        let parent = Int32(args[index + 1])!, tab = Int(args[index + 2])!
        let delegate: NSApplicationDelegate = telemetryRole
            ? TelemetryApplicationDelegate(parentPID: parent, tab: tab, frame: args[index + 3])
            : SettingsApplicationDelegate(parentPID: parent, tab: tab, frame: args[index + 3])
        app.delegate = delegate
        var closedAt: Double?
        let exitObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
            object: app, queue: .main) { _ in
            guard let closedAt, let path = ProcessInfo.processInfo.environment["ENDFIELD_RUNTIME_EXITS"],
                  let file = FileHandle(forWritingAtPath: path) else { return }
            let record: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier, "tab": tab,
                "close_seconds": ProcessInfo.processInfo.systemUptime - closedAt]
            var bytes = try! JSONSerialization.data(withJSONObject: record)
            bytes.append(0x0A)
            _ = try? file.seekToEnd(); try? file.write(contentsOf: bytes); try? file.close()
        }
        if telemetryRole && tab == 0 {
            _ = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
                app.windows.first(where: { $0.contentView is TelemetryView })?.miniaturize(nil)
            }
            _ = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: false) { _ in
                app.windows.first(where: { $0.contentView is TelemetryView })?.deminiaturize(nil)
            }
            _ = Timer.scheduledTimer(withTimeInterval: 1.3, repeats: false) { _ in app.hide(nil) }
            _ = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: false) { _ in app.unhide(nil) }
        }
        _ = Timer.scheduledTimer(withTimeInterval: telemetryRole && tab == 0 ? 2.0 : 0.8, repeats: false) { _ in
            guard let window = app.windows.first(where: { $0.isVisible && (telemetryRole ? $0.contentView is TelemetryView : $0.toolbar != nil) }) else {
                fputs("FAIL: child settings window missing\n", stderr); exit(1)
            }
            if !telemetryRole && ProcessInfo.processInfo.environment["ENDFIELD_RUNTIME_SHARING"] == "1" {
                guard let controller = window.windowController as? SettingsWindowController else { exit(1) }
                if tab == 0 {
                    var imported = Preferences()
                    imported.capsuleProfiles.append(.custom(title: "Actual pipe import"))
                    do { try controller.onConfigurationRequest?(.importShare(ConfigurationShare(preferences: imported), mode: .replace)) }
                    catch { fputs("FAIL: actual child import submit: \(error)\n", stderr); exit(1) }
                    guard controller.configurationPending else { fputs("FAIL: pending UI fence missing\n", stderr); exit(1) }
                    controller.selectedTab = 4
                    // PerformClose is the real user close path and must defer through the import ACK.
                    window.performClose(nil)
                    guard window.isVisible || (!controller.configurationPending && controller.settings.value.capsuleProfiles.contains(where: { $0.title == "Actual pipe import" })) else {
                        fputs("FAIL: pending import closed before acknowledgment\n", stderr); exit(1)
                    }
                } else {
                    guard controller.settings.value.capsuleProfiles.contains(where: { $0.title == "Actual pipe import" }) else {
                        fputs("FAIL: rapid reopen lost imported configuration\n", stderr); exit(1)
                    }
                    window.performClose(nil)
                }
                return
            }
            if telemetryRole {
                guard let view = window.contentView as? TelemetryView,
                      view.header.snapshot.percent == 68, view.header.preferences.scale == 0.75,
                      !view.header.preferences.powerTelemetryEnabled, view.graphSampleCount == 1 else {
                    fputs("FAIL: telemetry did not receive resident snapshot/preferences\n", stderr); exit(1)
                }
                if tab == 0 {
                    view.selectedTab = 4
                    window.setFrameOrigin(NSPoint(x: 120, y: 220))
                } else if tab != 4 || window.frame.origin != NSPoint(x: 120, y: 220) {
                    fputs("FAIL: telemetry reopen lost tab/position\n", stderr); exit(1)
                }
            } else if tab == 0 {
                guard let controller = window.windowController as? SettingsWindowController,
                      controller.settings.value.capsuleProfiles.count == 12,
                      controller.settings.value.capsuleProfiles.allSatisfy({ $0.title == byteMaximumName }),
                      controller.settings.value.telemetryAlertRules.count == 16,
                      controller.settings.value.telemetryAlertRules.allSatisfy({ $0.name == byteMaximumName }) else {
                    fputs("FAIL: child lost maximum Unicode configuration\n", stderr); exit(1)
                }
                guard let tabs = window.toolbar?.items.compactMap({ $0.view as? NSSegmentedControl }).first else {
                    fputs("FAIL: child settings tabs missing\n", stderr); exit(1)
                }
                tabs.selectedSegment = 6
                app.sendAction(tabs.action!, to: tabs.target, from: tabs)
                window.setFrameOrigin(NSPoint(x: 100, y: 200))
            } else if tab != 6 || window.frame.origin != NSPoint(x: 100, y: 200) {
                fputs("FAIL: child reopen lost tab/position\n", stderr); exit(1)
            }
            if telemetryRole {
                guard let button = window.contentView?.subviews.compactMap({ $0 as? NSButton }).first,
                      let action = button.action else {
                    fputs("FAIL: telemetry preview control missing\n", stderr); exit(1)
                }
                app.sendAction(action, to: button.target, from: button)
            } else {
                guard let controller = window.windowController as? SettingsWindowController,
                      controller.settings.value.capsuleProfiles.count == 12,
                      controller.settings.value.capsuleProfiles.allSatisfy({ $0.title == byteMaximumName }),
                      controller.settings.value.telemetryAlertRules.count == 16,
                      controller.settings.value.telemetryAlertRules.allSatisfy({ $0.name == byteMaximumName }) else {
                    fputs("FAIL: reopened child lost maximum Unicode configuration\n", stderr); exit(1)
                }
                (window.windowController as? SettingsWindowController)?.onCapsulePreview?(CapsuleProfile.cpuID)
                (window.windowController as? SettingsWindowController)?.onCapsulePreview?("unknown-profile")
                _ = delegate.applicationShouldHandleReopen?(app, hasVisibleWindows: true)
            }
            closedAt = ProcessInfo.processInfo.systemUptime
            window.close()
        }
        withExtendedLifetime((delegate, exitObserver)) { app.run() }
        exit(0)
    }
}
