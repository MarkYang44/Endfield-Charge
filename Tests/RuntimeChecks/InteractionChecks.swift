import AppKit
import ChargeCore

/// Minimal drag session carrying file URLs, so the real sharing drop target runs without a mouse.
private final class FileDrop: NSObject, NSDraggingInfo {
    let draggingPasteboard = NSPasteboard.withUniqueName()
    init(_ urls: [URL]) { super.init(); draggingPasteboard.writeObjects(urls.map { $0 as NSURL }) }
    deinit { draggingPasteboard.releaseGlobally() }
    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?,
        classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
}

/// Keyboard routing, the always-visible status line, jump links, dependent controls, window restore,
/// the menu's shortcut hint and drag-and-drop import.
func runInteractionChecks(domain: String) throws {
    let suite = domain + ".interaction"
    let defaults = UserDefaults(suiteName: suite)!
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("endfield-interaction-" + UUID().uuidString)
    let previousMenu = NSApp.mainMenu
    defer {
        NSApp.mainMenu = previousMenu
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
    let settings = AppSettings(defaults: defaults, persistsChanges: false)
    settings.value.language = "en"
    func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
    func key(_ characters: String) -> Bool {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: 0)!
        return NSApp.mainMenu?.performKeyEquivalent(with: event) == true
    }

    autoreleasepool {
        let controller = SettingsWindowController(settings: settings, selectedTab: 0, frame: nil,
            onPreview: { _ in }, onClose: { _, _ in })
        controller.installKeyboardMenu()
        controller.present()
        func all() -> [NSView] { views(controller.window!.contentView!) }
        func identified<T: NSView>(_ id: String, _ type: T.Type) -> T {
            guard let view = all().first(where: { $0.identifier?.rawValue == id }) as? T else { fatalError("FAIL: missing \(id)") }
            return view
        }
        let items = NSApp.mainMenu?.items.flatMap { $0.submenu?.items ?? [] } ?? []
        for (character, action) in [("c", #selector(NSText.copy(_:))), ("v", #selector(NSText.paste(_:))),
                                    ("x", #selector(NSText.cut(_:))), ("a", #selector(NSText.selectAll(_:))),
                                    ("w", #selector(NSWindow.performClose(_:))), ("m", #selector(NSWindow.performMiniaturize(_:)))] {
            check(items.contains { $0.keyEquivalent == character && $0.action == action && $0.keyEquivalentModifierMask == .command },
                  "Hidden UI menu routes Command-\(character.uppercased())")
        }
        let caps = all().compactMap { $0 as? NSButton }.filter { $0.cell is KeyCapCell }
        check(caps.count == 4 && caps.map(\.state) == [.off, .on, .on, .off], "Shortcut modifiers render as key caps that show the default Control-Option state")

        check(key("5") && controller.selectedTab == 4, "Command-5 opens Capsules without the toolbar")
        check(identified("settings.section", NSTextField.self).stringValue == "05 / CAPSULES", "Header indexes the open section")
        check(identified("footer.preview", NSButton.self).title == "Preview Active Capsule", "Capsules footer previews the edited capsule from any scroll position")
        let title = identified("profile.\(CapsuleProfile.batteryID).title", NSTextField.self)
        title.stringValue = ""
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: title))
        let status = identified("footer.status", NSTextField.self)
        check(status.textColor == .systemOrange && status.stringValue.contains("unsaved"), "Footer explains an invalid draft wherever its field is scrolled")
        title.stringValue = "BATTERY"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: title))
        check(status.stringValue == "Changes save automatically" && status.textColor == .secondaryLabelColor, "Footer returns to the auto-save hint once input is valid")

        check(key("2") && controller.selectedTab == 1, "Command-2 opens Display")
        check(identified("footer.preview", NSButton.self).title == "Preview Battery", "Other sections keep the battery preview")
        check(!all().contains { $0 is NSScrollView } && identified("playback.persistent", NSButton.self).frame.maxY <= 310,
              "Display fits above the footer with no hidden fold")
        all().compactMap { $0 as? LinkButton }.first!.performClick(nil)
        let scroll = all().compactMap { $0 as? NSScrollView }.first!
        let queue = controller.scrollAnchors["playback"] ?? 0
        let maximum = scroll.documentView!.frame.height - scroll.contentView.bounds.height
        check(controller.selectedTab == 4 && queue > 0 && abs(scroll.contentView.bounds.minY - min(maximum, queue - 12)) < 1,
              "Display's queue link lands on the Capsules playback section")
        all().compactMap { $0 as? LinkButton }.first!.performClick(nil)
        check(controller.selectedTab == 1, "Playback's persistent link returns to Display")

        settings.value.lowBatteryAlert = false
        check(key("3") && all().compactMap { $0 as? NSSlider }.allSatisfy { !$0.isEnabled }, "Low battery threshold is inactive while its alert is off")
        settings.value.lowBatteryAlert = true
        check(all().compactMap { $0 as? NSSlider }.allSatisfy(\.isEnabled), "Threshold follows its alert switch live")
        controller.window?.close()
    }

    autoreleasepool {
        let natural = SettingsWindowController(settings: settings, selectedTab: 0, frame: nil, onPreview: { _ in }, onClose: { _, _ in })
        let size = natural.window!.frame.size
        natural.window?.close()
        let visible = NSScreen.main!.visibleFrame
        let saved = NSRect(x: visible.minX + 40, y: visible.maxY - 40 - 999, width: 640, height: 999)
        let restored = SettingsWindowController(settings: settings, selectedTab: 0, frame: saved, onPreview: { _ in }, onClose: { _, _ in })
        let frame = restored.window!.frame
        check(frame.size == size && frame.minX == saved.minX && frame.maxY == saved.maxY, "Restore keeps the saved top-left with the current layout size")
        restored.window?.close()
        let stranded = SettingsWindowController(settings: settings, selectedTab: 0,
            frame: NSRect(x: -60_000, y: -60_000, width: size.width, height: size.height), onPreview: { _ in }, onClose: { _, _ in })
        check(NSScreen.screens.contains { $0.visibleFrame.intersects(stranded.window!.frame) }, "A position on a disconnected display recenters")
        stranded.window?.close()
        let terminal = TelemetryWindowController(settings: settings, selectedTab: 0, frame: nil, onPreview: {}, onClose: { _, _ in })
        terminal.installKeyboardMenu()
        check(key("4") && terminal.selectedTab == 3, "Command-4 opens the Network terminal page")
        terminal.window?.close()
    }

    let menu = StatusMenuController(settings: settings, target: NSObject(), entries: [("预览当前胶囊", "Preview Selected Capsule", #selector(NSObject.copy), "")],
        shortcutAction: #selector(NSObject.copy))
    menu.setShortcut(key: "H", modifiers: [.control, .option])
    check(menu.shortcutItem?.keyEquivalent == "h" && menu.shortcutItem?.keyEquivalentModifierMask == [.control, .option],
          "Status menu shows the registered global shortcut")
    menu.setShortcut(key: nil, modifiers: [.control, .option])
    check(menu.shortcutItem?.keyEquivalent == "", "An unregistered shortcut is not advertised")

    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var incoming = Preferences(); incoming.capsuleProfiles.append(.custom(title: "Dropped"))
    let file = directory.appendingPathComponent("drop.endfield.json")
    try ConfigurationShare(preferences: incoming).encoded().write(to: file)
    let text = directory.appendingPathComponent("notes.txt")
    try Data("x".utf8).write(to: text)
    let sharing = SettingsSharingController(settings: settings) { _ in }
    let target = sharing.window!.contentView!
    check(target.draggingEntered(FileDrop([text])) == [] && target.draggingEntered(FileDrop([file, file])) == [],
          "Sharing refuses non-JSON and multi-file drags")
    check(target.draggingEntered(FileDrop([file])) == .copy, "Sharing highlights one dragged share file")
    if let path = ProcessInfo.processInfo.environment["ENDFIELD_EDITOR_SCREENSHOTS"] {
        target.displayIfNeeded()
        let rep = target.bitmapImageRepForCachingDisplay(in: target.bounds)!
        target.cacheDisplay(in: target.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path).appendingPathComponent("sharing-drop-en.png"))
    }
    check(target.performDragOperation(FileDrop([file])), "Sharing accepts one dropped share file")
    let labels = views(target).compactMap { $0 as? NSTextField }.map(\.stringValue)
    let apply = views(target).compactMap { $0 as? NSButton }.first { $0.title == "Apply Import…" }
    check(labels.contains { $0.hasPrefix("Capsules: 1 added") } && apply?.isEnabled == true, "A dropped file opens the same reviewed import preview")
    sharing.close()
    print("PASS: hidden UI menu keys, footer status, section index, jump links, dependent threshold, restore, shortcut hint and drop import")
}
