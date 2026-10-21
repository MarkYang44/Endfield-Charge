import AppKit
import ChargeCore

// In-process checks of actual native owners and timers; never touches the user's preferences.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
// The same executable hosts the real child role, allowing an actual pipe/exit/reopen regression.
let unicodeName = String(repeating: "👨‍👩‍👧‍👦", count: 32)
func maximumUnicodePreferences() -> Preferences {
    var value = Preferences()
    for index in value.capsuleProfiles.indices { value.capsuleProfiles[index].title = unicodeName }
    for _ in 0..<7 { value.capsuleProfiles.append(.custom(title: unicodeName)) }
    value.telemetryAlertRules = (0..<16).map { _ in .custom(name: unicodeName) }
    return value
}
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
                  controller.settings.value.capsuleProfiles.allSatisfy({ $0.title == unicodeName }),
                  controller.settings.value.telemetryAlertRules.count == 16,
                  controller.settings.value.telemetryAlertRules.allSatisfy({ $0.name == unicodeName }) else {
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
                  controller.settings.value.capsuleProfiles.allSatisfy({ $0.title == unicodeName }),
                  controller.settings.value.telemetryAlertRules.count == 16,
                  controller.settings.value.telemetryAlertRules.allSatisfy({ $0.name == unicodeName }) else {
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
let domain = "com.markyang.endfieldcharge.runtime-checks.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: domain)!
defer { defaults.removePersistentDomain(forName: domain) }
let settings = AppSettings(defaults: defaults)
func spin(_ seconds: Double) { autoreleasepool { RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds)) } }
func awaitCondition(_ condition: () -> Bool, _ message: String) {
    let deadline = Date(timeIntervalSinceNow: 2)
    while !condition() && Date() < deadline { spin(0.01) }
    check(condition(), message)
}
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
try runEditorChecks()
if ProcessInfo.processInfo.environment["ENDFIELD_EDITORS_ONLY"] == "1" { exit(0) }
try runSharingChecks()
if ProcessInfo.processInfo.environment["ENDFIELD_SHARING_ONLY"] == "1" { exit(0) }
var appChanges = 0, uiChanges = 0
settings.onChange = { appChanges += 1 }
settings.onUIChange = { uiChanges += 1 }
let original = settings.value
settings.value = original
check(appChanges == 0 && uiChanges == 0, "Unchanged preferences must not notify/write")
settings.value.showPercentage = false
check(appChanges == 1 && uiChanges == 1, "App and UI notifications are independent")
let restored = AppSettings(defaults: defaults)
check(restored.value == settings.value, "All preferences survive saving/reloading")
let savedData = defaults.data(forKey: "preferences")
var peer = settings.value; peer.duration = 7
settings.applyFromPeer(peer)
check(settings.value.duration == 7 && defaults.data(forKey: "preferences") == savedData, "Peer updates apply without duplicate persistence")
print("PASS: preference guard, peer updates and independent app/UI callbacks")

let lockPath = FileManager.default.temporaryDirectory.appendingPathComponent("endfield-lock-check-\(UUID().uuidString)").path
var lock: ResidentInstance? = try ResidentInstance(path: lockPath)
do {
    _ = try ResidentInstance(path: lockPath)
    check(false, "Second resident must fail to acquire the lock")
} catch ResidentInstance.LockError.alreadyRunning(let pid) {
    check(pid == ProcessInfo.processInfo.processIdentifier, "Lock identifies the resident, not settings")
}
lock = nil
lock = try ResidentInstance(path: lockPath)
lock = nil
try FileManager.default.removeItem(atPath: lockPath)
print("PASS: resident-only locking and release")

let forward = Pipe(), backward = Pipe()
var parentChannel: SettingsChannel? = SettingsChannel(input: backward.fileHandleForReading, output: forward.fileHandleForWriting)
var childChannel: SettingsChannel? = SettingsChannel(input: forward.fileHandleForReading, output: backward.fileHandleForWriting)
var received: [Int] = []
parentChannel?.onMessage = { message in received.append(message.revision ?? -1) }
for revision in 0..<200 { childChannel?.send(SettingsMessage(.changed, preferences: peer, revision: revision)) }
let deadline = Date(timeIntervalSinceNow: 3)
while received.count < 200 && Date() < deadline { spin(0.05) }
check(received == Array(0..<200), "Rapid changes must arrive in order without loss")
var fragment = try JSONEncoder().encode(SettingsMessage(.closed, preferences: peer, revision: 200, tab: 2, frame: "{{100,200},{620,520}}"))
fragment.append(0x0A)
let split = fragment.count / 2
try backward.fileHandleForWriting.write(contentsOf: fragment.prefix(split))
spin(0.05)
check(received.count == 200, "Partial pipe frames must wait for completion")
try backward.fileHandleForWriting.write(contentsOf: fragment.suffix(fragment.count - split))
spin(0.1)
check(received.last == 200, "Fragmented final preferences/close state must decode")
var pipeEnded = false
parentChannel?.onEnd = { pipeEnded = true }
childChannel?.send(SettingsMessage(.closed, revision: 201))
childChannel?.flush { childChannel = nil }
let endDeadline = Date(timeIntervalSinceNow: 2)
while !pipeEnded && Date() < endDeadline { spin(0.05) }
check(pipeEnded && received.last == 201, "Final queued write must arrive before pipe EOF")
parentChannel = nil
print("PASS: 200 ordered pipe messages, fragmented frame and flushed final write before EOF")

// Use real pipes and the production channel: neither pre-split lines nor a substitute parser.
do {
    let incoming = Pipe(), outgoing = Pipe()
    let channel = SettingsChannel(input: incoming.fileHandleForReading, output: outgoing.fileHandleForWriting)
    var messages: [SettingsMessage] = []
    channel.onMessage = { messages.append($0) }
    func line(_ message: SettingsMessage) throws -> Data { try JSONEncoder().encode(message) + Data([10]) }
    func write(_ bytes: Data, fragmentSize: Int = 8192) throws {
        for offset in stride(from: 0, to: bytes.count, by: fragmentSize) {
            try incoming.fileHandleForWriting.write(contentsOf: bytes[offset..<min(offset + fragmentSize, bytes.count)])
            spin(0.01)
        }
        spin(0.03)
    }
    let maximum = maximumUnicodePreferences()
    let unicodeFrame = try line(SettingsMessage(.changed, preferences: maximum, revision: 1))
    check(unicodeFrame.count > 16_384, "Unicode regression exercises the former incomplete-frame cap")
    try write(unicodeFrame)
    check(messages.count == 1 && messages[0].preferences == maximum,
        "Maximum 12-profile/16-rule Unicode configuration survives actual 8192-byte pipe fragments")
    // Each frame is valid even when their combined write is larger than one frame's budget.
    let coalesced = try (2...7).reduce(into: Data()) { $0.append(try line(SettingsMessage(.changed, preferences: maximum, revision: $1))) }
    try write(coalesced, fragmentSize: coalesced.count)
    check(messages.compactMap(\.revision) == Array(1...7), "Coalesced valid frames are budgeted individually")
    let budget = SettingsMessage.maximumPayloadBytes
    var exact = SettingsMessage(.screen, frame: "")
    exact.frame = String(repeating: "x", count: budget - (try JSONEncoder().encode(exact)).count)
    let exactFrame = try line(exact)
    check(exactFrame.count == budget + 1, "Boundary frame payload excludes its newline")
    try write(exactFrame)
    check(messages.count == 8 && messages.last?.frame == exact.frame, "Exactly budget-sized inbound frame is accepted")
    let oversized = try line(SettingsMessage(.screen, frame: String(repeating: "x", count: budget + 1)))
    try write(oversized + line(SettingsMessage(.preview, revision: 8)), fragmentSize: oversized.count + 100)
    check(messages.count == 9 && messages.last?.revision == 8, "Complete oversized frame is rejected and following valid frame recovers")
    try write(oversized.dropLast())
    check(messages.count == 9, "Fragmented oversized frame remains discarded before its terminator")
    try write(Data([10]) + line(SettingsMessage(.preview, revision: 9)))
    check(messages.count == 10 && messages.last?.revision == 9, "Fragmented oversized frame drains through newline then resumes")
    let returnChannel = SettingsChannel(input: outgoing.fileHandleForReading, output: incoming.fileHandleForWriting)
    var outbound: [SettingsMessage] = []
    returnChannel.onMessage = { outbound.append($0) }
    channel.send(SettingsMessage(.screen, frame: String(repeating: "x", count: budget + 1)))
    channel.send(exact)
    channel.send(SettingsMessage(.closed, revision: 10))
    var flushed = false
    channel.flush { flushed = true }
    awaitCondition({ flushed && outbound.last?.revision == 10 }, "Outbound oversize rejection preserves ordered final-close flush")
    check(outbound.count == 2 && outbound[0].frame == exact.frame, "Outbound queue rejects overbudget payload and accepts exact limit")
}
print("PASS: maximum Unicode pipe configuration, coalescing, exact wire boundary, oversized drain/recovery and outbound budget")

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

let telemetrySample = TelemetrySnapshot(sampledAt: 100,
    battery: BatterySnapshot(hasBattery: true, percent: 68, currentMAh: 3400, fullMAh: 5000, voltageMV: 12000),
    power: PowerTelemetry(batteryWatts: -12, averageDischargeWatts: 10, adapterWatts: nil, cycleCount: 26),
    compute: ComputeTelemetry(cpuFraction: 0.25, memoryUsedBytes: 8 * 1_073_741_824,
        memoryTotalBytes: 24 * 1_073_741_824, compressedBytes: 1_073_741_824,
        swapUsedBytes: 0, pressure: .normal), thermal: .fair)
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

let telemetrySettings = AppSettings(defaults: defaults)
var sampler: TelemetryMonitor? = TelemetryMonitor(settings: telemetrySettings, battery: { telemetrySample.battery })
weak var releasedSampler = sampler
var telemetryUpdates = 0
var lastTelemetry: TelemetrySnapshot?
sampler?.onSnapshot = { telemetryUpdates += 1; lastTelemetry = $0 }
sampler?.start()
awaitCondition({ telemetryUpdates == 1 }, "Monitor promptly publishes its initial asynchronous sample")
sampler?.setPanelVisible(true)
spin(2.4)
check(telemetryUpdates >= 3, "Visible terminal enables 2-second native sampling")
sampler?.setPanelVisible(false)
awaitCondition({ lastTelemetry?.network == nil && lastTelemetry?.storage == nil }, "Hidden collector completion arrives")
check(lastTelemetry?.network == nil && lastTelemetry?.storage == nil,
    "Hiding terminal without profile/rule drops both on-demand snapshots")
let beforeCapsuleSample = telemetryUpdates
sampler?.setCapsuleMetrics([.networkDownloadBytesPerSecond])
awaitCondition({ telemetryUpdates > beforeCapsuleSample }, "Capsule baseline completes asynchronously")
check(lastTelemetry?.network?.downloadBytesPerSecond == nil && lastTelemetry?.network?.receivedBytes == 0,
    "Reenabled capsule starts fresh observation-session totals and unknown rate")
let beforeDismissSample = telemetryUpdates
sampler?.setCapsuleMetrics([])
awaitCondition({ telemetryUpdates > beforeDismissSample }, "Dismissed capsule publishes cleared readings")
let backgroundUpdates = telemetryUpdates
spin(2.4)
check(telemetryUpdates == backgroundUpdates, "Hidden terminal cancels the old 2-second timer")
telemetrySettings.value.powerTelemetryEnabled = false
telemetrySettings.value.computeTelemetryEnabled = false
telemetrySettings.value.thermalTelemetryEnabled = false
let beforeDisabledSample = telemetryUpdates
sampler?.preferencesChanged()
awaitCondition({ telemetryUpdates > beforeDisabledSample }, "Disabled modules publish unknown readings")
let stoppedUpdates = telemetryUpdates
spin(2.4)
check(telemetryUpdates == stoppedUpdates && lastTelemetry?.power == nil && lastTelemetry?.compute == nil && lastTelemetry?.thermal == nil,
    "Disabling every module stops timer and removes stale readings")
sampler?.stop(); sampler = nil
check(releasedSampler == nil, "Stopped native monitor releases observers and reader")
print("PASS: native sampler cadence, disabled modules and owner release")

// Demand and rule integration use a deterministic clock and actual resident routing.
var demandPreferences = Preferences()
demandPreferences.powerTelemetryEnabled = false
demandPreferences.computeTelemetryEnabled = false
demandPreferences.thermalTelemetryEnabled = false
check(!TelemetryDemand(preferences: demandPreferences, panelVisible: false, capsuleMetrics: []).hasWork,
    "Enabled on-demand modules alone never start polling")
check(TelemetryDemand(preferences: demandPreferences, panelVisible: true, capsuleMetrics: []).network,
    "Visible terminal requests network")
check(TelemetryDemand(preferences: demandPreferences, panelVisible: false,
    capsuleMetrics: [.networkDownloadBytesPerSecond]).highFrequency, "Visible network capsule requests fast shared cadence")
demandPreferences.telemetryAlertRules = [TelemetryAlertRule(id: "net-rule", name: "Network", enabled: true,
    metric: .networkDownloadBytesPerSecond, threshold: 100)]
check(TelemetryDemand(preferences: demandPreferences, panelVisible: false, capsuleMetrics: []).network,
    "Only a network rule still requests its enabled collector")
demandPreferences.networkTelemetryEnabled = false
check(!TelemetryDemand(preferences: demandPreferences, panelVisible: false, capsuleMetrics: []).hasWork,
    "Rules cannot force disabled modules on")
check(TelemetryDemand(preferences: demandPreferences, panelVisible: false, capsuleMetrics: [.batteryPercent]).hasWork,
    "Battery capsule uses existing power-monitor snapshot independently of telemetry toggles")
check(TelemetryFormatting.value(nil, metric: .networkDownloadBytesPerSecond) == "—",
    "Unknown metric is an em dash")
check(TelemetryFormatting.displayValue(1_048_576, metric: .networkDownloadBytesPerSecond) == 1,
    "Threshold editors convert base bytes per second to MiB per second")
let demandSettings = AppSettings(defaults: defaults)
demandSettings.value = demandPreferences
var ruleClock = 1.0
var ruleRate = 200.0
let ruleMonitor = TelemetryMonitor(settings: demandSettings, battery: { telemetrySample.battery },
    clock: { ruleClock }, read: { _, _ in TelemetrySnapshot(sampledAt: ruleClock,
        battery: telemetrySample.battery, power: nil, compute: nil, thermal: nil,
        network: NetworkTelemetry(downloadBytesPerSecond: ruleRate,
        uploadBytesPerSecond: nil, receivedBytes: 0, sentBytes: 0, interfaces: ["en0"])) })
var firedRules: [String] = []
ruleMonitor.onRuleAlert = { rule, _ in firedRules.append(rule.id) }
ruleMonitor.start()
check(ruleMonitor.samplingInterval == nil && ruleMonitor.latestSnapshot?.network == nil,
    "All disabled stops timer and strips unavailable routing")
demandSettings.value.networkTelemetryEnabled = true
ruleMonitor.preferencesChanged()
check(ruleMonitor.samplingInterval == 30 && firedRules.isEmpty, "Rule-only demand is background; startup does not alert")
ruleClock = 2; ruleRate = 0; ruleMonitor.refresh()
ruleClock = 3; ruleRate = 200; ruleMonitor.refresh()
check(firedRules == ["net-rule"], "Recovered crossing routes one resident rule alert")
ruleClock = 4; ruleRate = 0; ruleMonitor.refresh()
ruleClock = 5; ruleRate = 200; ruleMonitor.refresh()
check(firedRules.count == 1, "Resident respects evaluator cooldown")
ruleMonitor.setCapsuleMetrics([.networkDownloadBytesPerSecond])
check(ruleMonitor.samplingInterval == 2, "Capsule uses same visible shared timer")
ruleMonitor.setCapsuleMetrics([])
check(ruleMonitor.samplingInterval == 30, "Dismissed capsule restores background rule cadence")
ruleMonitor.resetAfterWake()
ruleClock = 40; ruleMonitor.refresh()
check(firedRules.count == 1, "Wake clears rule baseline without replay")
ruleMonitor.stop()
print("PASS: demand transitions, unit scaling, disabled routing and resident rule lifecycle")

// Exercise the actual bounded asynchronous pipeline with a deliberately blocked collector.
final class BlockingCollector {
    let lock = NSLock()
    let release = DispatchSemaphore(value: 0)
    private var count = 0
    private var active = 0
    private var maximum = 0
    private var readOnMain = false
    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
    var activeCount: Int { lock.lock(); defer { lock.unlock() }; return active }
    var maximumActive: Int { lock.lock(); defer { lock.unlock() }; return maximum }
    var touchedMain: Bool { lock.lock(); defer { lock.unlock() }; return readOnMain }
    func read(_ battery: BatterySnapshot, _ demand: TelemetryDemand) -> TelemetrySnapshot {
        lock.lock(); count += 1; active += 1; maximum = max(maximum, active)
        readOnMain = readOnMain || Thread.isMainThread
        let index = count; lock.unlock()
        _ = release.wait(timeout: .now() + 10)
        lock.lock(); active -= 1; lock.unlock()
        return TelemetrySnapshot(sampledAt: Double(index), battery: battery,
            power: nil, compute: nil, thermal: nil,
            network: NetworkTelemetry(downloadBytesPerSecond: 100, uploadBytesPerSecond: 0,
                receivedBytes: 0, sentBytes: 0, interfaces: ["en0"]))
    }
}
let asyncSettings = AppSettings(defaults: defaults)
asyncSettings.value = Preferences()
let blocker = BlockingCollector()
var batteryReadOnMain = true
var asyncMonitor: TelemetryMonitor? = TelemetryMonitor(settings: asyncSettings, battery: {
    batteryReadOnMain = batteryReadOnMain && Thread.isMainThread
    return telemetrySample.battery
}, asyncRead: { battery, demand, _ in blocker.read(battery, demand) })
weak var releasedAsyncMonitor = asyncMonitor
var asyncPublications: [Double] = []
var publishedOnMain = true
asyncMonitor?.onSnapshot = {
    publishedOnMain = publishedOnMain && Thread.isMainThread
    asyncPublications.append($0.sampledAt)
}
asyncMonitor?.start()
var mainContinued = false
DispatchQueue.main.async { mainContinued = true }
awaitCondition({ mainContinued && blocker.calls == 1 }, "Main loop continues while collector is blocked")
check(!blocker.touchedMain && batteryReadOnMain, "Read runs on worker while battery capture stays on main")
for _ in 0..<100 { asyncMonitor?.refresh() }
asyncSettings.value.networkTelemetryEnabled = false
asyncMonitor?.preferencesChanged()
spin(0.05)
check(blocker.calls == 1, "Rapid refreshes never enqueue overlapping collector work")
blocker.release.signal()
awaitCondition({ blocker.calls == 2 }, "Blocked refreshes coalesce into one latest request")
check(asyncPublications.isEmpty, "Preference change discards the inflight stale completion")
blocker.release.signal()
awaitCondition({ asyncPublications == [2] }, "Only latest coalesced preference request publishes")
check(asyncMonitor?.latestSnapshot?.network == nil, "Latest preference snapshot gates worker fields")
asyncMonitor?.refresh()
awaitCondition({ blocker.calls == 3 }, "Next blocked read begins")
asyncMonitor?.setPanelVisible(true)
blocker.release.signal()
awaitCondition({ blocker.calls == 4 }, "Changed demand replaces blocked request")
check(asyncPublications == [2], "Demand change discards old completion")
blocker.release.signal()
awaitCondition({ asyncPublications == [2, 4] }, "Latest demand publishes")
asyncMonitor?.refresh()
awaitCondition({ blocker.calls == 5 }, "Pre-wake read begins")
asyncMonitor?.resetAfterWake()
blocker.release.signal()
awaitCondition({ blocker.calls == 6 }, "Wake schedules latest reset request")
check(asyncPublications == [2, 4], "Wake rejects pre-wake completion")
blocker.release.signal()
awaitCondition({ asyncPublications == [2, 4, 6] }, "Post-wake reset request publishes")
asyncMonitor?.refresh()
awaitCondition({ blocker.calls == 7 }, "Pre-stop read begins")
asyncMonitor?.stop()
blocker.release.signal()
awaitCondition({ blocker.activeCount == 0 }, "Stopped read finishes without blocking main")
spin(0.05)
check(asyncPublications == [2, 4, 6] && asyncMonitor?.latestSnapshot == nil, "Stop rejects inflight completion")
asyncMonitor?.start()
awaitCondition({ blocker.calls == 8 }, "Restart uses serial worker")
asyncMonitor?.stop(); asyncMonitor = nil
check(releasedAsyncMonitor == nil, "Blocked collector closures do not retain monitor owner")
blocker.release.signal()
awaitCondition({ blocker.activeCount == 0 }, "Released owner's worker finishes safely")
check(blocker.maximumActive == 1 && publishedOnMain, "One serial collector and main-only publication")
// Wrap the real production reader to prove a coalesced disable/re-enable still resets its baseline.
let nativeGate = BlockingCollector()
let resetSettings = AppSettings(defaults: defaults)
resetSettings.value = Preferences()
let resetMonitor = TelemetryMonitor(settings: resetSettings, battery: { telemetrySample.battery },
    asyncRead: { battery, demand, collect in
        _ = nativeGate.read(battery, demand)
        return collect()
    })
var resetSnapshots: [TelemetrySnapshot] = []
resetMonitor.onSnapshot = { resetSnapshots.append($0) }
resetMonitor.setCapsuleMetrics([.networkDownloadBytesPerSecond])
resetMonitor.start()
awaitCondition({ nativeGate.calls == 1 }, "Real reader waits off-main before initial baseline")
resetMonitor.setCapsuleMetrics([])
resetMonitor.setCapsuleMetrics([.networkDownloadBytesPerSecond])
nativeGate.release.signal()
awaitCondition({ nativeGate.calls == 2 }, "Real latest request follows coalesced demand changes")
check(resetSnapshots.isEmpty, "Old real-reader baseline is not published")
nativeGate.release.signal()
awaitCondition({ resetSnapshots.count == 1 }, "Real collector publishes the latest reenabled demand")
check(resetSnapshots[0].network?.downloadBytesPerSecond == nil && resetSnapshots[0].network?.receivedBytes == 0,
    "Coalesced disabled network still resets rates and observation-session totals")
resetMonitor.stop()
print("PASS: blocked asynchronous collector responsiveness, bounded coalescing, stale generations and owner release")

settings.value.duration = 4
runPlaybackChecks()

let hud = HUDController(settings: settings)
let initial = BatterySnapshot(hasBattery: true, percent: 76, externalPower: true, isCharging: true)
let alert = BatterySnapshot(hasBattery: true, percent: 19)
func visibleHUD() -> HUDView? {
    autoreleasepool {
        app.windows.first(where: { $0.isVisible && $0.contentView is HUDView })?.contentView as? HUDView
    }
}
weak var releasedHUD: HUDView?
autoreleasepool {
hud.show(initial)
spin(2.75)
check(visibleHUD()?.kind == .power, "Initial HUD reaches static hold")
hud.show(alert, kind: .lowBattery, queued: true)
spin(0.1)
check(visibleHUD()?.kind == .power, "Alert queues instead of interrupting the static hold")
spin(1.3)
check(visibleHUD()?.kind == .lowBattery, "Queued alert plays after the first HUD closes")
let interrupted = BatterySnapshot(hasBattery: true, percent: 50)
hud.show(interrupted)
check(visibleHUD()?.snapshot.percent == 50, "Nonqueued preview interrupts immediately")
releasedHUD = visibleHUD()
spin(4.2)
check(visibleHUD() == nil, "Finished HUD is no longer visible")
}
check(releasedHUD == nil, "Finished HUD view/backing owner deallocates")
print("PASS: static-hold queue, preview interruption and HUD release")

let networkProfile = CapsuleProfile.defaults.first { $0.id == CapsuleProfile.networkID }!
var capsuleDemand: Set<TelemetryMetric> = []
hud.onCapsuleDemand = { capsuleDemand = $0 }
hud.showProfile(networkProfile, snapshot: telemetrySample)
check(capsuleDemand.contains(.networkDownloadBytesPerSecond), "Profile requests metric while visible")
check(visibleHUD()?.capsule?.primary == "—" && visibleHUD()?.capsule?.ringFraction == nil,
    "Missing profile sample keeps unknown text and ring")
var networkSample = telemetrySample
networkSample.network = NetworkTelemetry(downloadBytesPerSecond: 1_048_576, uploadBytesPerSecond: 0,
    receivedBytes: 0, sentBytes: 0, interfaces: ["en0"])
hud.updateTelemetry(networkSample)
check(visibleHUD()?.capsule?.primary == "1.0", "Resident samples update the actual visible payload during hold")
hud.show(alert, kind: .lowBattery, queued: true)
hud.show(initial)
check(capsuleDemand.isEmpty && visibleHUD()?.capsule == nil, "Power interruption clears demand and queued custom content")
hud.dismiss()
check(visibleHUD() == nil && capsuleDemand.isEmpty, "Dismissal releases profile view and demand immediately")
let customRule = TelemetryAlertRule(id: "queued-native-rule", name: "Storage warning", enabled: true,
    metric: .storageAvailableBytes, comparison: .below, threshold: 1_073_741_824)
settings.value.telemetryAlertRules = [customRule]
hud.showRule(customRule, snapshot: networkSample)
check(visibleHUD()?.capsule?.alert == true, "Generic rule uses the capsule alert presentation")
settings.value.telemetryAlertRules = []
hud.preferencesChanged()
check(visibleHUD() == nil && capsuleDemand.isEmpty, "Deleting a rule releases active alert and demand")
settings.value.networkTelemetryEnabled = false
hud.showProfile(networkProfile, snapshot: networkSample)
check(visibleHUD()?.capsule?.primary == "—", "Disabled network renders unknown despite cached resident values")
hud.dismiss()
settings.value.networkTelemetryEnabled = true
var replayAtRelease = false
hud.onCapsuleDemand = { metrics in
    capsuleDemand = metrics
    if metrics.isEmpty && replayAtRelease { replayAtRelease = false; hud.show(initial) }
}
hud.showProfile(networkProfile, snapshot: networkSample)
replayAtRelease = true
spin(4.15)
check(visibleHUD() != nil, "A synchronous fresh event during demand release retains its new HUD owner")
hud.dismiss()
let longProfile = CapsuleProfile(id: "long-render", title: String(repeating: "终末测量", count: 8),
    primaryMetric: .storageAvailableBytes, secondaryMetric: .networkDownloadBytesPerSecond, ringMetric: .cpuPercent)
try FileManager.default.createDirectory(atPath: "/private/tmp/endfield-plus-task2-hud", withIntermediateDirectories: true)
let renderCapsule = HUDView(frame: NSRect(x: 0, y: 0, width: 620, height: 144))
renderCapsule.capsule = CapsulePresentation(profile: longProfile, snapshot: networkSample)
for stage in [1.55, 3.0] {
    renderCapsule.elapsed = stage
    try renderCapsule.writePNG(to: URL(fileURLWithPath: "/private/tmp/endfield-plus-task2-hud/custom-\(stage).png"))
}
renderCapsule.reduceMotion = true; renderCapsule.elapsed = 0.15
try renderCapsule.writePNG(to: URL(fileURLWithPath: "/private/tmp/endfield-plus-task2-hud/custom-reduced.png"))
print("PASS: profile unknown/live payload, power interruption and demand release")

settings.value.duration = 3
for _ in 0..<3 {
    autoreleasepool { hud.show(initial) }
    spin(3.2)
    check(visibleHUD() == nil, "Repeated HUD has no lingering visible panel")
}
weak var releasedActiveHUD: HUDView?
var activeDemand: Set<TelemetryMetric> = []
autoreleasepool {
    var transient: HUDController? = HUDController(settings: settings)
    transient?.onCapsuleDemand = { activeDemand = $0 }
    transient?.showProfile(networkProfile, snapshot: networkSample)
    releasedActiveHUD = visibleHUD()
    transient = nil
}
spin(0.1)
check(releasedActiveHUD == nil && activeDemand.isEmpty, "Releasing active HUD owner clears its surface and demand")
print("PASS: repeated animation lifecycle")

// A bare test executable has a separate defaults domain from the installed application.
let standardPreferences = UserDefaults.standard.data(forKey: "preferences")
var fixture = maximumUnicodePreferences()
fixture.scale = 0.85; fixture.duration = 3; fixture.showPercentage = false
settings.value = fixture
UserDefaults.standard.set(try JSONEncoder().encode(Preferences()), forKey: "preferences")
UserDefaults.standard.synchronize()
var previews = 0
var profilePreviews: [String] = []
var settingsProcess: SettingsProcessController?
var displayContext: UInt32?
let exitsURL = FileManager.default.temporaryDirectory.appendingPathComponent("endfield-runtime-exits-\(UUID().uuidString)")
FileManager.default.createFile(atPath: exitsURL.path, contents: Data())
let previousExitsPath = ProcessInfo.processInfo.environment["ENDFIELD_RUNTIME_EXITS"]
setenv("ENDFIELD_RUNTIME_EXITS", exitsURL.path, 1)
settingsProcess = SettingsProcessController(settings: settings, onPreview: { _ in
    previews += 1
    // Child has queued preview then close; parent sends show then acknowledgment.
    // The closing child must flush its reopen request and parent must drain EOF before release.
    if previews == 1 { settingsProcess?.open() }
}, onScreen: { displayContext = $0 })
settingsProcess?.onCapsulePreview = { profilePreviews.append($0) }
settingsProcess?.open()
let reopenDeadline = Date(timeIntervalSinceNow: 7)
while previews < 2 && Date() < reopenDeadline { spin(0.05) }
spin(0.3)
check(previews == 2, "Immediate show/closeAck must reopen a fresh settings process")
check(profilePreviews == [CapsuleProfile.cpuID, CapsuleProfile.cpuID],
    "Typed child profile preview forwards valid resident IDs and rejects unknown IDs")
check(settings.value == fixture, "Child preferences survive ready/close/reopen without stale overwrite")
check(displayContext == nil, "Closed child clears context for future previews")
let exits = try String(contentsOf: exitsURL, encoding: .utf8).split(separator: "\n").map {
    try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
}
check(exits.count == 2, "Both settings children terminate naturally before the test stops them")
for record in exits {
    check((record["close_seconds"] as! Double) < 1.5, "Close acknowledgment exits before the 2-second fallback")
    check(kill((record["pid"] as! NSNumber).int32Value, 0) == -1 && errno == ESRCH, "Closed child is no longer a process")
}
settingsProcess?.stop(); settingsProcess = nil
settings.value.scale = 0.75
settings.value.powerTelemetryEnabled = false
settings.value.computeTelemetryEnabled = false
settings.value.thermalTelemetryEnabled = false
var telemetryProcess: SettingsProcessController?
var telemetryPreviews = 0
var visibility: [Bool] = []
telemetryProcess = SettingsProcessController(settings: settings, role: .telemetry, onPreview: { _ in
    telemetryPreviews += 1
    if telemetryPreviews == 1 { telemetryProcess?.open() }
}, onScreen: { displayContext = $0 })
telemetryProcess?.onVisibility = { visibility.append($0) }
var olderTelemetry = telemetrySample
olderTelemetry.battery.percent = 67
olderTelemetry.power = nil; olderTelemetry.compute = nil; olderTelemetry.thermal = nil
telemetryProcess?.sendTelemetry(olderTelemetry)
telemetryProcess?.open()
_ = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
    telemetryProcess?.updateBattery(telemetrySample.battery)
}
let telemetryReopenDeadline = Date(timeIntervalSinceNow: 7)
while telemetryPreviews < 2 && Date() < telemetryReopenDeadline { spin(0.05) }
spin(0.3)
check(telemetryPreviews == 2, "Telemetry close acknowledgment drains and rapidly reopens")
check(settings.value.scale == 0.75, "Telemetry child never overwrites resident preferences from its defaults")
check(visibility == [true, false, true, false, true, false, true, false],
    "Minimize/hide return to background and restoration/reopen return to visible sampling")
let allExits = try String(contentsOf: exitsURL, encoding: .utf8).split(separator: "\n").map {
    try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
}
check(allExits.count == 4, "Both telemetry children terminate naturally")
for record in allExits.suffix(2) {
    check((record["close_seconds"] as! Double) < 1.5, "Telemetry closes by acknowledgement before fallback")
    check(kill((record["pid"] as! NSNumber).int32Value, 0) == -1 && errno == ESRCH, "Closed telemetry child is no longer running")
}
telemetryProcess?.stop(); telemetryProcess = nil
let orphan = Process(), orphanInput = Pipe(), orphanOutput = Pipe()
orphan.executableURL = Bundle.main.executableURL
orphan.arguments = ["--telemetry-ui", String(ProcessInfo.processInfo.processIdentifier), "0", "center"]
orphan.standardInput = orphanInput; orphan.standardOutput = orphanOutput
try orphan.run()
spin(0.2)
try orphanInput.fileHandleForWriting.close()
let eofDeadline = Date(timeIntervalSinceNow: 1.5)
while orphan.isRunning && Date() < eofDeadline { spin(0.05) }
check(!orphan.isRunning && orphan.terminationStatus == 0, "Telemetry child exits naturally on parent pipe EOF")
if let previousExitsPath { setenv("ENDFIELD_RUNTIME_EXITS", previousExitsPath, 1) } else { unsetenv("ENDFIELD_RUNTIME_EXITS") }
try FileManager.default.removeItem(at: exitsURL)
UserDefaults.standard.set(standardPreferences, forKey: "preferences")
print("PASS: actual child process, preview, close acknowledgment, rapid reopen and tab/frame preservation")
print("PASS: telemetry delivery, preference direction, visibility, acknowledged close and rapid reopen")
print("PASS: telemetry child exits on parent EOF without fallback")
print("All 24 native runtime check groups passed")
