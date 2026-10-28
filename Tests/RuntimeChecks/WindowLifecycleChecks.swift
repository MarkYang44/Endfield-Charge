import AppKit
import ChargeCore

func runWindowLifecycleChecks(settings: AppSettings, domain: String) throws {
    var owner: SettingsWindowController?
    var savedTab = -1
    var savedFrame = NSRect.zero
    weak var releasedController: SettingsWindowController?
    weak var releasedWindow: NSWindow?
    autoreleasepool {
        owner = SettingsWindowController(settings: settings, selectedTab: 2, frame: nil, onPreview: { _ in }, onClose: { tab, frame in
            savedTab = tab; savedFrame = frame; owner = nil
        })
        releasedController = owner
        releasedWindow = owner?.window
        owner?.present()
        owner?.window?.setFrameOrigin(NSPoint(x: 100, y: 200))
        owner?.window?.close()
    }
    spin(0.1)
    check(savedTab == 2 && savedFrame.origin == NSPoint(x: 100, y: 200), "Close preserves tab and position")
    check(releasedController == nil && releasedWindow == nil, "Closed settings controller/window must deallocate")
    check(settings.onUIChange == nil && settings.onChange != nil, "Closing UI detaches only the UI callback")
    print("PASS: settings window release and preserved reopen state")

    autoreleasepool {
        let controller = SettingsWindowController(settings: settings, selectedTab: 6, frame: nil,
            onPreview: { _ in }, onClose: { _, _ in })
        check(controller.selectedTab == 6, "Seven settings tabs accept About at index six")
        let tabs = controller.window?.toolbar?.items.compactMap { $0.view as? NSSegmentedControl }.first
        check(tabs?.segmentCount == 7, "Seven native settings segments are present")
        let terminal = TelemetryView(settings: settings, selectedTab: 4)
        check(terminal.selectedTab == 4, "Five terminal tabs accept Storage at index four")
        controller.window?.close()
    }
    autoreleasepool {
        let languageDefaults = UserDefaults(suiteName: domain + ".language")!
        defer { languageDefaults.removePersistentDomain(forName: domain + ".language") }
        let languageSettings = AppSettings(defaults: languageDefaults)
        languageSettings.value.language = "en"
        let terminal = TelemetryWindowController(settings: languageSettings, selectedTab: 3, frame: nil,
            onPreview: {}, onClose: { _, _ in })
        let tabs = terminal.view.subviews.compactMap { $0 as? NSSegmentedControl }.first!
        check(tabs.label(forSegment: 3) == "NETWORK", "English telemetry tabs preserve the terminal theme")
        languageSettings.value.language = "zh"
        check((0..<5).map { tabs.label(forSegment: $0) ?? "" } == ["电源", "计算", "散热", "网络", "存储"],
            "Live language changes relabel all five existing telemetry tabs")
        check(!terminal.view.headerTimerActive && terminal.selectedTab == 3, "Language switching preserves selected page without starting sampling or animation")
        languageSettings.value.language = "en"
        check(tabs.label(forSegment: 4) == "STORAGE", "Existing telemetry controls switch back to English")
        terminal.window?.close()
    }
    for tab in 0..<7 {
        autoreleasepool {
            let controller = SettingsWindowController(settings: settings, selectedTab: tab, frame: savedFrame,
                onPreview: { _ in }, onClose: { _, _ in })
            controller.present()
            check(controller.window?.frame == savedFrame, "Reopened frame remains identical")
            check(!controller.bindings.isEmpty || tab == 6 || tab == 5, "Current page controls are bound")
            controller.window?.close()
        }
    }
    spin(0.1)
    print("PASS: all seven lazy settings pages can open/close")
}
