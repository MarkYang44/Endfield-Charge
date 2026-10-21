import AppKit
import ChargeCore

func runEditorChecks() throws {
    func check(_ ok: Bool, _ message: String) { if !ok { fputs("FAIL: editor \(message)\n", stderr); exit(1) } }
    let domain = "endfield-editors-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let settings = AppSettings(defaults: defaults, persistsChanges: false)
    settings.value.language = "en"
    let c = SettingsWindowController(settings: settings, selectedTab: 4, frame: nil, onPreview: { _ in }, onClose: { _,_ in })
    defer { c.close() }
    check(!settings.value.playback.persistent && !settings.value.playback.rotationEnabled, "Playback features default off")
    c.present()
    func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
    func control<T: NSControl>(_ id: String, _ type: T.Type = T.self) -> T {
        guard let v = views(c.window!.contentView!).first(where: { $0.identifier?.rawValue == id }) as? T else {
            fatalError("FAIL: editor missing actual control \(id)")
        }; return v
    }
    func click(_ id: String) { control(id, NSButton.self).performClick(nil) }
    func select(_ id: String, _ index: Int) {
        let p = control(id, NSPopUpButton.self); p.selectItem(at: index); c.controlChanged(p)
    }
    func enter(_ id: String, _ text: String) {
        let f = control(id, NSTextField.self); f.stringValue = text
        c.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: f))
    }
    let id = CapsuleProfile.batteryID
    click("appearance.add")
    check(settings.value.capsuleProfiles[0].colorConditions.count == 1, "Add writes actual condition")
    let scroll = views(c.window!.contentView!).compactMap { $0 as? NSScrollView }.first!
    scroll.contentView.scroll(to: NSPoint(x: 0, y: 430))
    select("appearance.metric", TelemetryMetric.allCases.firstIndex(of: .memoryUsedBytes)!)
    check(views(c.window!.contentView!).compactMap { $0 as? NSScrollView }.first!.contentView.bounds.minY == 430, "Rebuild preserves appearance editing scroll position")
    enter("profile.\(id).color.0.threshold", "2.5")
    check(settings.value.capsuleProfiles[0].colorConditions[0].threshold == 2.5 * 1_073_741_824, "Threshold uses human GiB")
    select("appearance.comparison", 1); select("appearance.accent", 3)
    check(settings.value.capsuleProfiles[0].colorConditions[0].comparison == .below && settings.value.capsuleProfiles[0].colorConditions[0].accent == .red, "Strict comparator and typed palette bound")
    click("appearance.add"); click("appearance.add"); click("appearance.add")
    check(settings.value.capsuleProfiles[0].colorConditions.count == 4 && !control("appearance.add", NSButton.self).isEnabled, "Maximum four colors")
    select("appearance.selector", 2)
    enter("profile.\(id).color.2.threshold", "bad")
    let before = settings.value.capsuleProfiles[0].colorConditions
    let profileChoice = views(c.window!.contentView!).compactMap { $0 as? NSPopUpButton }.first { $0.itemArray.contains { $0.representedObject as? String == id } }!
    profileChoice.selectItem(at: 1); c.controlChanged(profileChoice)
    check(settings.value.selectedCapsuleID == id && profileChoice.selectedItem?.representedObject as? String == id, "Blocked capsule switch restores visible selection")
    select("appearance.metric", 0)
    check(settings.value.capsuleProfiles[0].colorConditions == before, "Invalid draft blocks metric switch")
    click("appearance.up")
    check(settings.value.capsuleProfiles[0].colorConditions == before && c.validationMessage?.stringValue.isEmpty == false, "Invalid draft blocks reorder with explanation")
    select("appearance.selector", 0); click("appearance.delete")
    check(settings.value.capsuleProfiles[0].colorConditions.count == 4, "Delete before invalid draft cannot shift its owner")
    c.selectedTab = 1; c.buildPage(); c.selectedTab = 4; c.buildPage()
    check(c.draftText["profile.\(id).color.2.threshold"] == "bad", "Draft survives tab rebuild")
    enter("profile.\(id).color.2.threshold", "42")
    click("appearance.up")
    check(settings.value.capsuleProfiles[0].colorConditions[1].threshold == 42, "Corrected condition moves in order")
    click("appearance.down"); click("appearance.up")
    check(settings.value.capsuleProfiles[0].colorConditions[1].threshold == 42, "Condition down/up preserves logical payload")
    click("appearance.delete")
    check(settings.value.capsuleProfiles[0].colorConditions.count == 3, "Remove actual selected condition")
    var previews: [String] = []; c.onCapsulePreview = { previews.append($0) }
    click("appearance.preview"); check(previews == [id], "Preview routes through resident callback")
    // Real field editor marked text must block structural edits even before validation.
    let f = control("profile.\(id).color.1.threshold", NSTextField.self)
    c.window?.makeFirstResponder(f)
    if let editor = f.currentEditor() as? NSTextView {
        editor.setMarkedText("未", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let n = settings.value.capsuleProfiles[0].colorConditions.count
        c.controlChanged(control("appearance.add", NSButton.self))
        check(settings.value.capsuleProfiles[0].colorConditions.count == n && editor.hasMarkedText(), "IME draft blocks structural edits without unmarking")
        editor.unmarkText(); f.stringValue = "42"; c.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: f)); c.commitEditing()
    } else { check(false, "Actual IME editor available") }
    select("appearance.selector", 2); click("appearance.delete")
    check(settings.value.capsuleProfiles[0].colorConditions.count == 2, "Deleting last visible condition does not refresh an out-of-range binding")
    c.selectedTab = 5; c.buildPage()
    // Existing Add is intentionally located by title to verify the preserved native rule editor.
    (views(c.window!.contentView!).compactMap { $0 as? NSButton }.first { $0.title == "Add" })!.performClick(nil)
    let ruleID = settings.value.telemetryAlertRules[0].id
    select("rule.kind", 1); select("rule.source", 1)
    select("rule.target", 2)
    check(settings.value.telemetryAlertRules[0].targetState == .memoryPressure(.warning), "Known typed memory target")
    select("rule.target", 0)
    check(settings.value.telemetryAlertRules[0].targetState == nil, "Any change has no invented target")
    select("rule.target", 2)
    select("rule.source", 0)
    check(settings.value.telemetryAlertRules[0].targetState == nil && control("rule.target", NSPopUpButton.self).numberOfItems == 5, "Source switch clears incompatible target, excludes unknown")
    enter("rule.\(ruleID).hold", "12"); enter("rule.\(ruleID).cooldown", "60")
    check(settings.value.telemetryAlertRules[0].holdSeconds == 12 && settings.value.telemetryAlertRules[0].cooldownSeconds == 60, "State hold/cooldown bound")
    c.selectedTab = 4; c.buildPage()
    click("playback.add"); select("playback.available", 0); click("playback.add")
    check(settings.value.playback.profileIDs.count == 2 && Set(settings.value.playback.profileIDs).count == 2, "Queue adds unique available IDs")
    let queue = settings.value.playback.profileIDs
    click("playback.up"); check(settings.value.playback.profileIDs == queue.reversed(), "Queue moves in order")
    enter("playback.interval", "600"); enter("playback.interval", "9")
    check(settings.value.playback.intervalSeconds == 600, "Invalid dwell stays draft")
    enter("playback.interval", "10")
    click("playback.rotation")
    check(settings.value.playback.rotationEnabled, "Rotation toggle bound")
    click("playback.delete"); click("playback.delete")
    check(settings.value.playback.profileIDs.isEmpty && !settings.value.playback.rotationEnabled && control("playback.rotation", NSButton.self).state == .off, "Empty queue normalizes rotation UI immediately")
    (views(c.window!.contentView!).compactMap { $0 as? NSButton }.first { $0.title == "Add" })!.performClick(nil)
    let customID = settings.value.selectedCapsuleID
    select("playback.available", control("playback.available", NSPopUpButton.self).numberOfItems - 1)
    click("playback.add"); click("playback.rotation")
    check(settings.value.playback.profileIDs == [customID], "Custom profile is queued by identity")
    (views(c.window!.contentView!).compactMap { $0 as? NSButton }.first { $0.title == "Delete" })!.performClick(nil)
    check(settings.value.playback.profileIDs.isEmpty && !settings.value.playback.rotationEnabled, "Deleting queued profile normalizes empty queue immediately")
    c.selectedTab = 1; c.buildPage(); click("playback.persistent")
    check(settings.value.playback.persistent, "Persistent Display toggle bound")
    c.setConfigurationPending(true)
    for tab in [1,4,5] {
        c.selectedTab = tab; c.buildPage()
        check(views(c.window!.contentView!).compactMap { $0 as? NSControl }.allSatisfy { !$0.isEnabled }, "Rebuilt editor respects transaction fence")
    }
    c.setConfigurationPending(false)
    print("PASS: native bound appearance/state/playback editor controls, drafts, IME and pending fence")
    if let path = ProcessInfo.processInfo.environment["ENDFIELD_EDITOR_SCREENSHOTS"] {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        settings.value.playback.profileIDs = settings.value.capsuleProfiles.map(\.id)
        settings.value.playback.rotationEnabled = true
        for language in ["en", "zh"] {
            settings.value.language = language
            for (tab, name) in [(1,"display"),(4,"capsules"),(5,"rules")] {
                c.selectedTab = tab; c.buildPage(); c.window?.displayIfNeeded()
                let root = c.window!.contentView!
                let scroll = views(root).compactMap { $0 as? NSScrollView }.first!
                let height = scroll.documentView!.frame.height
                let captures: [(String, CGFloat)] = tab == 4
                    ? [("0",0),("1",430),("2",790),("3",height - 310),("appearance-aligned",480),("queue-aligned",830),("appearance-docs",450)]
                    : [("0",0),("1",height - 310)]
                for (index, offset) in captures {
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, offset))); scroll.reflectScrolledClipView(scroll.contentView)
                    root.displayIfNeeded()
                    let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds)!
                    root.cacheDisplay(in: root.bounds, to: rep)
                    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path).appendingPathComponent("\(name)-\(language)-\(index).png"))
                }
            }
        }
        print("PASS: isolated English/Chinese actual settings screenshot exports")
    }
}
