import AppKit
import ChargeCore

func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
func press(_ control: NSControl) {
    check(control.isEnabled, "Requested native control is enabled")
    guard let action = control.action else { check(false, "Native action exists"); return }
    app.sendAction(action, to: control.target, from: control)
}
func field(_ controller: SettingsWindowController, _ key: String) -> NSTextField {
    guard let content = controller.window?.contentView,
          let field = descendants(content).compactMap({ $0 as? NSTextField }).first(where: { $0.identifier?.rawValue == key }) else {
        check(false, "Editor field exists: \(key)"); fatalError()
    }
    return field
}
func input(_ controller: SettingsWindowController, key: String, text: String) {
    let field = field(controller, key)
    controller.window?.makeFirstResponder(field)
    guard let editor = field.currentEditor() as? NSTextView else { check(false, "Actual AppKit field editor is active"); return }
    editor.selectAll(nil)
    editor.insertText(text, replacementRange: editor.selectedRange())
    field.validateEditing()
    controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
}
func button(_ controller: SettingsWindowController, title: String) -> NSButton {
    descendants(controller.window!.contentView!).compactMap { $0 as? NSButton }.first { $0.title == title }!
}

func runNativeEditorChecks(domain: String) throws {
    var editorPreferences = Preferences()
    editorPreferences.language = "en"
    let editorDefaults = UserDefaults(suiteName: domain + ".editors")!
    defer { editorDefaults.removePersistentDomain(forName: domain + ".editors") }
    let editorSettings = AppSettings(defaults: editorDefaults)
    editorSettings.value = editorPreferences
    let exactReference = 100.1234567890123
    editorSettings.value.capsuleProfiles[0].referenceMaximum = exactReference
    autoreleasepool {
        let untouched = SettingsWindowController(settings: editorSettings, selectedTab: 4, frame: nil,
            onPreview: { _ in }, onClose: { _, _ in })
        untouched.present(); untouched.window?.close()
    }
    check(editorSettings.value.capsuleProfiles[0].referenceMaximum == exactReference,
        "Opening and closing a numeric editor must not round an untouched persisted value")
    autoreleasepool {
        let reviewDomain = domain + ".review"
        let reviewDefaults = UserDefaults(suiteName: reviewDomain)!
        defer { reviewDefaults.removePersistentDomain(forName: reviewDomain) }
        let reviewSettings = AppSettings(defaults: reviewDefaults)
        reviewSettings.value.language = "en"
        let controller = SettingsWindowController(settings: reviewSettings, selectedTab: 4, frame: nil,
            onPreview: { _ in }, onClose: { _, _ in })
        controller.present()
        var findings: [String] = []
        func expect(_ value: Bool, _ message: String) { if !value { findings.append(message) } }
        press(button(controller, title: "Add"))
        let customID = reviewSettings.value.selectedCapsuleID
        input(controller, key: "profile.\(customID).title", text: "")
        let selector = descendants(controller.window!.contentView!).compactMap { $0 as? NSPopUpButton }.first { $0.accessibilityLabel() == "Active capsule" }!
        selector.selectItem(at: 0); press(selector)
        let batteryPrefix = "profile.\(CapsuleProfile.batteryID)."
        input(controller, key: batteryPrefix + "title", text: "")
        input(controller, key: batteryPrefix + "maximum", text: "nan")
        press(button(controller, title: "Restore Built-ins"))
        expect(reviewSettings.value.capsuleProfiles.first == CapsuleProfile.defaults[0], "Restore persists the original battery profile")
        expect(field(controller, batteryPrefix + "title").stringValue == "BATTERY", "Restore clears invalid built-in title draft")
        expect(field(controller, batteryPrefix + "maximum").stringValue == "100", "Restore clears invalid built-in maximum draft")
        expect(!controller.draftText.keys.contains { $0.hasPrefix(batteryPrefix) }, "Restored built-in fields have no stale draft keys")
        expect(controller.draftText["profile.\(customID).title"] == "", "Restore preserves unrelated custom draft text")
        reviewSettings.value.networkTelemetryEnabled = false
        controller.editProfile(CapsuleProfile.batteryID) { $0.ringMetric = .networkDownloadBytesPerSecond }
        controller.buildPage()
        let labels = descendants(controller.window!.contentView!).compactMap { $0 as? NSTextField }.map(\.stringValue)
        expect(labels.contains { $0.hasPrefix("Selected metric module is disabled") }, "An available primary with disabled ring reports unavailable input")
        reviewSettings.value.language = "zh"
        press(button(controller, title: "复制"))
        let copy = reviewSettings.value.capsuleProfiles.first { $0.id == reviewSettings.value.selectedCapsuleID }
        expect(copy?.title == "BATTERY 副本", "Chinese native duplicate generates a localized suffix")
        let terminal = TelemetryView(settings: reviewSettings, selectedTab: 1)
        let rowLabels = descendants(terminal).compactMap { $0 as? NSTextField }.map(\.stringValue)
        expect(rowLabels.contains("交换空间") && !rowLabels.contains("Swap"), "Chinese Compute page localizes the Swap row")
        controller.window?.close()
        check(findings.isEmpty, "Review regressions: " + findings.joined(separator: "; "))
    }
    print("PASS: restore clears only built-in drafts, disabled ring availability, Chinese Swap and duplicate suffix")

    weak var releasedEditorField: NSTextField?
    autoreleasepool {
        var controller: SettingsWindowController? = SettingsWindowController(settings: editorSettings, selectedTab: 4,
            frame: nil, onPreview: { _ in }, onClose: { _, _ in })
        controller!.present()
        press(button(controller!, title: "Add"))
        let id = editorSettings.value.selectedCapsuleID
        check(editorSettings.value.capsuleProfiles.count == 6 && !id.hasPrefix("builtin."), "Add creates/selects a custom profile")
        let titleKey = "profile.\(id).title"
        input(controller!, key: titleKey, text: "Pending native title")
        editorSettings.shortcutMessage = "Refresh while editing"
        check(field(controller!, titleKey).currentEditor()?.string == "Pending native title", "Binding refresh preserves active text")
        let overbyteName = "e" + String(repeating: "\u{301}", count: 600)
        input(controller!, key: titleKey, text: overbyteName)
        check(editorSettings.value.capsuleProfiles.first { $0.id == id }?.title == "Pending native title"
            && controller!.draftText[titleKey] == overbyteName && field(controller!, titleKey).textColor == .systemOrange,
            "Character-valid overbyte capsule name stays orange and unsaved")
        check(field(controller!, titleKey).toolTip?.contains("1024") == true, "Invalid-input hint discloses UTF-8 byte bound")
        input(controller!, key: titleKey, text: unicodeName)
        controller!.commitEditing()
        check(editorSettings.value.capsuleProfiles.first { $0.id == id }?.title == unicodeName,
            "Valid 32-family-emoji capsule title saves without truncation")
        input(controller!, key: titleKey, text: "Pending native title")
        let title = field(controller!, titleKey)
        let editor = title.currentEditor() as! NSTextView
        editor.selectAll(nil)
        editor.setMarkedText("输入中", selectedRange: NSRange(location: 3, length: 0), replacementRange: editor.selectedRange())
        title.validateEditing()
        controller!.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: title))
        editorSettings.shortcutMessage = "Refresh with marked composition"
        check(editor.hasMarkedText() && editor.string == "输入中", "Peer refresh keeps IME composition intact")
        controller!.commitEditing()
        check(editorSettings.value.capsuleProfiles.first { $0.id == id }?.title == "输入中", "Composition commits at navigation boundary")
        let popups = descendants(controller!.window!.contentView!).compactMap { $0 as? NSPopUpButton }
        let ring = popups.first { $0.accessibilityLabel() == "Ring metric" }!
        ring.select(ring.itemArray.first { $0.representedObject as? String == TelemetryMetric.memoryUsedBytes.rawValue })
        press(ring)
        check(editorSettings.value.capsuleProfiles.first { $0.id == id }?.referenceMaximum == 16 * 1_073_741_824, "Ring metric change chooses meaningful GiB default")
        let changedRing = descendants(controller!.window!.contentView!).compactMap { $0 as? NSPopUpButton }.first { $0.accessibilityLabel() == "Ring metric" }!
        changedRing.select(changedRing.itemArray.first { $0.representedObject as? String == TelemetryMetric.networkDownloadBytesPerSecond.rawValue })
        press(changedRing)
        check(editorSettings.value.capsuleProfiles.first { $0.id == id }?.referenceMaximum == 10 * 1_048_576, "Changing an existing ring does not replay an old-unit text field")
        let restoredRing = descendants(controller!.window!.contentView!).compactMap { $0 as? NSPopUpButton }.first { $0.accessibilityLabel() == "Ring metric" }!
        restoredRing.select(restoredRing.itemArray.first { $0.representedObject as? String == TelemetryMetric.memoryUsedBytes.rawValue })
        press(restoredRing)
        input(controller!, key: "profile.\(id).maximum", text: "24")
        check(editorSettings.value.capsuleProfiles.first { $0.id == id }?.referenceMaximum == 24 * 1_073_741_824, "GiB editor stores bytes")
        for invalid in ["", "nan", "inf", "1e309", "-1", "0"] {
            input(controller!, key: "profile.\(id).maximum", text: invalid)
            check(editorSettings.value.capsuleProfiles.first { $0.id == id }?.referenceMaximum == 24 * 1_073_741_824, "Invalid reference does not mutate persisted profile: \(invalid)")
        }
        let profileSelector = descendants(controller!.window!.contentView!).compactMap { $0 as? NSPopUpButton }.first { $0.accessibilityLabel() == "Active capsule" }!
        profileSelector.selectItem(at: 0); press(profileSelector)
        let reselect = descendants(controller!.window!.contentView!).compactMap { $0 as? NSPopUpButton }.first { $0.accessibilityLabel() == "Active capsule" }!
        reselect.select(reselect.itemArray.first { $0.representedObject as? String == id }); press(reselect)
        check(field(controller!, "profile.\(id).maximum").stringValue == "0", "Invalid draft survives profile switch without persisting")
        let tabControl = controller!.window!.toolbar!.items.compactMap { $0.view as? NSSegmentedControl }.first!
        tabControl.selectedSegment = 0; press(tabControl)
        tabControl.selectedSegment = 4; press(tabControl)
        check(field(controller!, "profile.\(id).maximum").stringValue == "0", "Invalid draft survives lazy tab destruction")
        input(controller!, key: "profile.\(id).maximum", text: "32")
        var previewID: String?
        controller!.onCapsulePreview = { previewID = $0 }
        press(button(controller!, title: "Preview Active Capsule"))
        check(previewID == id, "Preview routes the edited typed profile ID")
        press(button(controller!, title: "Duplicate"))
        check(editorSettings.value.capsuleProfiles.count == 7 && editorSettings.value.selectedCapsuleID != id, "Duplicate uses a fresh stable ID")
        press(button(controller!, title: "Delete"))
        check(editorSettings.value.capsuleProfiles.count == 6 && editorSettings.value.selectedCapsuleID == CapsuleProfile.batteryID, "Delete selects the retained default battery")
        let tabs = controller!.window!.toolbar!.items.compactMap { $0.view as? NSSegmentedControl }.first!
        tabs.selectedSegment = 5; press(tabs)
        press(button(controller!, title: "Add"))
        let ruleID = editorSettings.value.telemetryAlertRules[0].id
        check(!editorSettings.value.telemetryAlertRules[0].enabled, "New rules are disabled")
        let metric = descendants(controller!.window!.contentView!).compactMap { $0 as? NSPopUpButton }.first { $0.accessibilityLabel() == "Metric" }!
        metric.select(metric.itemArray.first { $0.representedObject as? String == TelemetryMetric.networkUploadBytesPerSecond.rawValue })
        press(metric)
        input(controller!, key: "rule.\(ruleID).threshold", text: "2.5")
        check(editorSettings.value.telemetryAlertRules[0].threshold == 2.5 * 1_048_576, "MiB/s threshold stores bytes per second")
        input(controller!, key: "rule.\(ruleID).hold", text: "301")
        input(controller!, key: "rule.\(ruleID).cooldown", text: "9")
        check(editorSettings.value.telemetryAlertRules[0].holdSeconds == 0 && editorSettings.value.telemetryAlertRules[0].cooldownSeconds == 30, "Out-of-range hold/cooldown stay unsaved")
        input(controller!, key: "rule.\(ruleID).hold", text: "12.5")
        input(controller!, key: "rule.\(ruleID).cooldown", text: "120")
        button(controller!, title: "Enable this rule").performClick(nil)
        check(editorSettings.value.telemetryAlertRules[0].enabled, "Native checkbox enables only the selected user rule")
        input(controller!, key: "rule.\(ruleID).name", text: overbyteName)
        check(editorSettings.value.telemetryAlertRules[0].name == "ALERT"
            && field(controller!, "rule.\(ruleID).name").textColor == .systemOrange,
            "Character-valid overbyte rule name stays orange and unsaved")
        input(controller!, key: "rule.\(ruleID).name", text: unicodeName)
        check(editorSettings.value.telemetryAlertRules[0].name == unicodeName, "Valid 32-family-emoji rule name saves whole")
        input(controller!, key: "rule.\(ruleID).name", text: "Close commits pending")
        let pendingName = field(controller!, "rule.\(ruleID).name")
        let pendingEditor = pendingName.currentEditor() as! NSTextView
        pendingEditor.selectAll(nil)
        pendingEditor.setMarkedText(unicodeName, selectedRange: NSRange(location: (unicodeName as NSString).length, length: 0), replacementRange: pendingEditor.selectedRange())
        pendingName.validateEditing()
        controller!.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: pendingName))
        check(editorSettings.value.telemetryAlertRules[0].name == "Close commits pending", "Unfinished IME composition stays unsaved before close")
        releasedEditorField = pendingName
        controller!.window?.close()
        controller = nil
        let restored = AppSettings(defaults: editorDefaults)
        check(restored.value.telemetryAlertRules[0].name == unicodeName
            && restored.value.telemetryAlertRules[0].holdSeconds == 12.5
            && restored.value.telemetryAlertRules[0].cooldownSeconds == 120, "Native pending edits survive close and disk reload")
    }
    spin(0.1)
    check(releasedEditorField == nil, "Editor text field/delegate/actions release with lazy page owner")
    for invalid in ["nan", "inf", "-inf", "", ".", "1e308"] {
        check(SettingsNumeric.parse(invalid, metric: .memoryUsedBytes, positive: true) == nil, "Finite unit conversion rejects malformed/overflow values")
    }
    print("PASS: native capsule/rule editing, human units, malformed numbers, pending text/IME, preview, persistence and release")
}
