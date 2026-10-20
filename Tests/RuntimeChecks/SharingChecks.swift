import AppKit
import ChargeCore

func runSharingChecks() throws {
    func check(_ condition: Bool, _ message: String) { if !condition { fputs("FAIL: \(message)\n", stderr); exit(1) } }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("endfield-sharing-" + UUID().uuidString)
    let domain = "endfield-sharing-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: directory) }
    let store = ConfigurationBackupStore(directory: directory)
    let resident = AppSettings(defaults: defaults)
    let original = resident.value
    try store.save(original)
    var changed = original; changed.language = "zh"
    try store.save(changed)
    check(try store.load() == changed, "Backup atomically replaces complete preferences")
    check(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1, "Only one backup is retained")
    let valid = try Data(contentsOf: store.fileURL)
    var invalid = original; invalid.capsuleProfiles[0].title = String(repeating: "X", count: 33)
    do { try store.save(invalid); check(false, "Invalid backup must fail") } catch {}
    check(try Data(contentsOf: store.fileURL) == valid, "Invalid backup preserves prior snapshot")
    try Data("{}".utf8).write(to: store.fileURL)
    do { _ = try store.load(); check(false, "Malformed backup must fail") } catch {}
    let blocked = directory.appendingPathComponent("blocked")
    try Data().write(to: blocked)
    do { try ConfigurationBackupStore(directory: blocked).save(original); check(false, "Blocked backup directory must fail") } catch {}
    let blockedAtomic = ConfigurationBackupStore(directory: directory.appendingPathComponent("atomic"))
    try FileManager.default.createDirectory(at: blockedAtomic.fileURL, withIntermediateDirectories: true)
    do { try blockedAtomic.save(original); check(false, "Atomic write failure must propagate") } catch {}
    let bounded = directory.appendingPathComponent("bounded")
    let cap = Data(repeating: 32, count: SettingsMessage.maximumPayloadBytes)
    try cap.write(to: bounded)
    check(try ConfigurationFileIO.readBounded(bounded) == cap, "Bounded file reader accepts exact 128 KiB")
    try (cap + Data([32])).write(to: bounded)
    do { _ = try ConfigurationFileIO.readBounded(bounded); check(false, "Oversize file must fail") } catch ConfigurationShareError.fileTooLarge {}
    print("PASS: permanent backup atomic/error preservation and bounded file checks")

    let helperDefaults = UserDefaults(suiteName: domain + ".helper")!
    defer { helperDefaults.removePersistentDomain(forName: domain + ".helper") }
    let helper = AppSettings(defaults: helperDefaults, persistsChanges: false)
    helper.value.language = "zh" // A stale child snapshot must never initialize its parent.
    let service = ConfigurationTransactionService(settings: resident, backupStore: store)
    let toParent = Pipe(), toHelper = Pipe()
    let parent = SettingsChannel(input: toParent.fileHandleForReading, output: toHelper.fileHandleForWriting)
    let child = SettingsChannel(input: toHelper.fileHandleForReading, output: toParent.fileHandleForWriting)
    let session = SettingsConfigurationSession(settings: helper, send: { child.send($0) })
    var commits = 0, results: [ConfigurationTransactionResult] = []
    var requests: [ConfigurationTransactionRequest] = []
    resident.onChange = { commits += 1 }
    parent.onMessage = {
        if let request = $0.transactionRequest { requests.append(request) }
        if let response = service.receive($0) { parent.send(response) }
    }
    child.onMessage = { session.receive($0) }
    session.onResult = { results.append($0) }
    session.start()
    awaitCondition({ session.initialized }, "Authoritative ready response arrives over private pipes")
    check(helper.value == original && resident.value == original && commits == 0, "Ready uses resident preferences without callback echo")
    helper.value.duration = 7
    helper.value.scale = 0.9
    helper.value.showPercentage = false
    awaitCondition({ resident.value == helper.value }, "Pipelined edits chain baselines before ACK without losing changes")
    check(commits == 3 && helperDefaults.data(forKey: "preferences") == nil, "Resident alone persists ordinary helper edits")
    var incoming = Preferences(); incoming.capsuleProfiles.append(.custom(title: "Imported"))
    incoming.telemetryAlertRules = [.custom(name: "Imported rule")]
    let share = try ConfigurationShare(preferences: incoming)
    let beforeCommits = commits + 2
    helper.value.duration = 8
    helper.value.scale = 0.8
    let before = helper.value // These changes have not received an ACK when import is queued.
    try session.submit(.importShare(share, mode: .replace))
    check(session.pending, "Transaction sets pending fence synchronously")
    check(session.closed(tab: 4, frame: "center").preferences == nil, "Pending close never includes a pre-import snapshot")
    do { try session.submit(.restoreBackup); check(false, "A second pending request must fail") } catch {}
    awaitCondition({ !session.pending }, "Import result arrives over private pipes")
    check(results.last?.status == .applied && commits == beforeCommits + 1, "Resident commits import exactly once")
    check(helper.value == resident.value && helper.value.language == before.language && helper.value.scale == before.scale,
          "Import acknowledgment is authoritative and preserves local settings")
    check(try store.load() == before, "Import backs up full preferences before mutation")
    check(helperDefaults.data(forKey: "preferences") == nil, "Authoritative result cannot save or echo helper preferences")
    let afterImport = resident.value
    let repeated = service.receive(SettingsMessage(.configurationRequest, transactionRequest: requests.last!))!
    check(repeated.transactionResult?.status == .stale && commits == beforeCommits + 1, "Replaying a correlated request cannot commit twice")
    let pendingClose = SettingsMessage(.closed, preferences: before, revision: 0)
    _ = service.receive(pendingClose)
    check(resident.value == afterImport, "Legacy stale close without baseline cannot overwrite imported configuration")
    let close = session.closed(tab: 4, frame: "center")
    _ = service.receive(close)
    check(commits == beforeCommits + 1 && resident.value == afterImport, "Close after acknowledgment cannot replay old preferences")
    let staleClosed = SettingsMessage(.closed, preferences: before, revision: 1,
        baselineDigest: try ConfigurationTransactionRequest.digest(before))
    _ = service.receive(staleClosed)
    check(resident.value == afterImport, "Late pre-import close snapshot cannot overwrite imported state")
    let stale = try ConfigurationTransactionRequest(requestID: UUID().uuidString, expectedRevision: session.revision,
        baseline: helper.value, action: .restoreBackup)
    resident.value.showPercentage.toggle() // Resident status menu edit, without helper revision.
    let menuValue = resident.value
    let staleResult = service.receive(SettingsMessage(.configurationRequest, transactionRequest: stale))!
    check(staleResult.transactionResult?.status == .stale && resident.value == menuValue, "Digest catches menu edits outside UI revision")
    session.receive(service.state(.ready))
    let undoCommits = commits
    try session.submit(.restoreBackup)
    awaitCondition({ !session.pending }, "Restore result arrives")
    check(results.last?.status == .applied && resident.value == before && commits == undoCommits + 1,
          "Explicit undo restores full snapshot once")
    check(try store.load() == before, "Restore does not replace the last import backup")
    try Data("{}".utf8).write(to: store.fileURL)
    let failureCommits = commits
    try session.submit(.restoreBackup)
    awaitCondition({ !session.pending }, "Malformed restore returns explicit failure")
    check(results.last?.failure == .backupUnavailable && resident.value == before && commits == failureCommits,
          "Restore failure preserves active preferences")
    let failedService = ConfigurationTransactionService(settings: resident, backupStore: ConfigurationBackupStore(directory: blocked))
    let failureRequest = try ConfigurationTransactionRequest(requestID: UUID().uuidString, expectedRevision: failedService.state(.ready).revision!,
        baseline: resident.value, action: .importShare(share, mode: .replace))
    check(failedService.receive(SettingsMessage(.configurationRequest, transactionRequest: failureRequest))?.transactionResult?.failure == .storageFailure,
          "Backup failure rejects import")
    check(resident.value == before && commits == failureCommits, "Backup failure cannot partially commit")
    // A canceled preview submits nothing; a mismatched or late result cannot mutate local drafts.
    let preview = try share.preview(mode: .merge, local: helper.value)
    check(preview.preferences != helper.value && resident.value == before, "Preview and cancellation do not mutate either owner")
    var sent: [SettingsMessage] = []
    let local = AppSettings(defaults: helperDefaults, persistsChanges: false)
    let late = SettingsConfigurationSession(settings: local, send: { sent.append($0) })
    late.receive(service.state(.ready))
    try late.submit(.importShare(share, mode: .replace))
    let request = sent.last!.transactionRequest!
    let applied = service.receive(SettingsMessage(.configurationRequest, transactionRequest: request))!
    local.value.duration = 9
    late.receive(SettingsMessage(.configurationResult, preferences: before, revision: 999,
        transactionResult: ConfigurationTransactionResult(requestID: "unrelated", status: .applied)))
    check(late.pending && local.value.duration == 9, "Uncorrelated result cannot clear pending request or overwrite drafts")
    late.receive(applied)
    check(local.value.duration == 9 && !late.pending, "Late transaction result cannot overwrite a newer local edit")
    let fresh = AppSettings(defaults: helperDefaults, persistsChanges: false)
    let reopened = SettingsConfigurationSession(settings: fresh, send: { _ in })
    reopened.receive(service.state(.ready))
    check(fresh.value == resident.value, "Rapid reopen initializes from authoritative import instead of stale child defaults")
    try late.submit(.restoreBackup)
    check(late.pending, "EOF regression starts with an active transaction")
    late.disconnect()
    check(!late.pending, "Parent EOF clears transaction fence")
    print("PASS: actual private-pipe ready, pipelined edits, import/undo, stale/menu/close/reopen and failure transactions")

    // Real settings-role subprocess: import then immediately close, and reopen against stale defaults.
    let previousSharing = ProcessInfo.processInfo.environment["ENDFIELD_RUNTIME_SHARING"]
    setenv("ENDFIELD_RUNTIME_SHARING", "1", 1)
    defer {
        if let previousSharing { setenv("ENDFIELD_RUNTIME_SHARING", previousSharing, 1) } else { unsetenv("ENDFIELD_RUNTIME_SHARING") }
    }
    let actual = AppSettings(defaults: defaults)
    actual.value = Preferences(); actual.value.language = "en"
    let beforeActual = actual.value
    var launches = 0, closes = 0
    var actualCommits = 0
    actual.onChange = { actualCommits += 1 }
    var process: SettingsProcessController?
    process = SettingsProcessController(settings: actual, onPreview: { _ in }, onScreen: { _ in },
        backupStore: ConfigurationBackupStore(directory: directory.appendingPathComponent("actual")))
    process?.onVisibility = { visible in
        if visible { launches += 1 }
        else { closes += 1; if closes == 1 { process?.open() } }
    }
    process?.open()
    let deadline = Date(timeIntervalSinceNow: 7)
    while closes < 2 && Date() < deadline { spin(0.03) }
    process?.stop(); process = nil
    check(launches == 2 && closes == 2, "Actual settings child imports, defers close, exits and reopens")
    check(actual.value.capsuleProfiles.contains(where: { $0.title == "Actual pipe import" }) && actualCommits == 1,
          "Actual resident pipe transaction persists exactly once across close/reopen")
    check(try ConfigurationBackupStore(directory: directory.appendingPathComponent("actual")).load() == beforeActual,
          "Actual resident used injected backup directory")
    print("PASS: actual subprocess import acknowledgment, deferred close and authoritative rapid reopen")

    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    func button(_ window: NSWindow, _ title: String) -> NSButton {
        let buttons = descendants(window.contentView!).compactMap { $0 as? NSButton }
        guard let match = buttons.first(where: { $0.title == title }) else {
            fputs("FAIL: missing button \(title), available: \(buttons.map(\.title))\n", stderr); exit(1)
        }
        return match
    }
    func answerSheet(_ window: NSWindow, title: String) {
        awaitCondition({ window.attachedSheet != nil }, "Confirmation is presented")
        let sheet = window.attachedSheet!
        button(sheet, title).performClick(nil)
        spin(0.06)
    }
    let screenshotDirectory = URL(fileURLWithPath: "/private/tmp/endfield-capsule-sharing/task-4-screenshots")
    try FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
    func screenshot(_ view: NSView, _ name: String) throws {
        view.window?.displayIfNeeded()
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: screenshotDirectory.appendingPathComponent(name + ".png"))
    }
    for language in ["en", "zh"] {
        let localSettings = AppSettings(defaults: helperDefaults, persistsChanges: false)
        localSettings.value = Preferences(); localSettings.value.language = language
        let chinese = language == "zh"
        var actions: [ConfigurationTransactionAction] = []
        let editor = SettingsWindowController(settings: localSettings, selectedTab: 4, frame: nil,
            onPreview: { _ in }, onClose: { _, _ in })
        editor.onConfigurationRequest = { [weak editor] action in actions.append(action); editor?.setConfigurationPending(true) }
        editor.showWindow(nil)
        try screenshot(editor.window!.contentView!, "capsules-" + language)
        let scroll = descendants(editor.window!.contentView!).compactMap { $0 as? NSScrollView }.first!
        scroll.documentView!.scroll(NSPoint(x: 0, y: scroll.documentView!.bounds.height))
        try screenshot(editor.window!.contentView!, "capsules-bottom-" + language)
        editor.showSharing()
        let sharing = editor.sharingController!
        try screenshot(sharing.window!.contentView!, "sharing-empty-" + language)
        try sharing.prepareImport(share.encoded())
        try screenshot(sharing.window!.contentView!, "sharing-merge-" + language)
        let popup = descendants(sharing.window!.contentView!).compactMap { $0 as? NSPopUpButton }.first!
        popup.selectItem(at: 1); NSApp.sendAction(popup.action!, to: popup.target, from: popup)
        try screenshot(sharing.window!.contentView!, "sharing-replace-" + language)
        let initial = localSettings.value
        let apply = button(sharing.window!, chinese ? "应用导入…" : "Apply Import…")
        apply.performClick(nil)
        answerSheet(sharing.window!, title: chinese ? "取消" : "Cancel")
        check(actions.isEmpty && localSettings.value == initial, "Canceling import confirmation mutates nothing")
        apply.performClick(nil)
        answerSheet(sharing.window!, title: chinese ? "确认" : "Confirm")
        check(actions.count == 1 && sharing.pending && editor.configurationPending, "Native Apply submits one resident transaction and fences both windows")
        check(!popup.isEnabled && !apply.isEnabled, "Sharing controls disable during pending transaction")
        editor.buildPage() // Display/layout notifications can rebuild a pending page.
        check(descendants(editor.window!.contentView!).compactMap { $0 as? NSControl }.allSatisfy { !$0.isEnabled },
              "A page rebuilt during a transaction keeps the edit fence")
        editor.window!.performClose(nil)
        check(editor.window!.isVisible, "Main window close is deferred while transaction is pending")
        sharing.window!.performClose(nil)
        check(sharing.window!.isVisible, "Sharing window close cannot abandon pending transaction")
        editor.setConfigurationPending(false)
        check(!editor.window!.isVisible, "Deferred close completes after authoritative result")
        // Restore confirmation is explicit and localized too.
        let undo = SettingsSharingController(settings: localSettings) { actions.append($0) }
        undo.showWindow(nil)
        button(undo.window!, chinese ? "撤销上次导入…" : "Undo Last Import…").performClick(nil)
        answerSheet(undo.window!, title: chinese ? "取消" : "Cancel")
        check(actions.count == 1, "Canceling restore confirmation does not submit")
        button(undo.window!, chinese ? "撤销上次导入…" : "Undo Last Import…").performClick(nil)
        answerSheet(undo.window!, title: chinese ? "确认" : "Confirm")
        check(actions.last == .restoreBackup, "Restore confirmation submits typed resident action")
        undo.completed(ConfigurationTransactionResult(requestID: "failure", status: .rejected, failure: .backupUnavailable))
        try screenshot(undo.window!.contentView!, "sharing-error-" + language)
        undo.close()
    }
    let overflowSettings = AppSettings(defaults: helperDefaults, persistsChanges: false)
    overflowSettings.value = Preferences(); overflowSettings.value.language = "en"
    overflowSettings.value.capsuleProfiles += (0..<7).map { .custom(title: "Local \($0)") }
    let overflowUI = SettingsSharingController(settings: overflowSettings) { _ in }
    do { try overflowUI.prepareImport(share.encoded()) }
    catch { check(false, "A valid file that exceeds merge limits must stay available for Replace") }
    let overflowPopup = descendants(overflowUI.window!.contentView!).compactMap { $0 as? NSPopUpButton }.first!
    overflowPopup.selectItem(at: 1); NSApp.sendAction(overflowPopup.action!, to: overflowPopup.target, from: overflowPopup)
    check(button(overflowUI.window!, "Apply Import…").isEnabled, "Replace remains usable when merge exceeds limits")
    check(!descendants(overflowUI.window!.contentView!).compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("exceed 12") },
          "Switching to a valid Replace preview clears the old merge-limit failure")
    overflowUI.close()
    let languageEditor = SettingsWindowController(settings: overflowSettings, selectedTab: 4, frame: nil,
        onPreview: { _ in }, onClose: { _, _ in })
    languageEditor.showSharing()
    overflowSettings.value.language = "zh"
    check(languageEditor.sharingController?.window?.title == "分享与导入", "Visible sharing window follows in-app language changes")
    languageEditor.sharingController?.window?.performClose(nil)
    check(languageEditor.sharingController == nil, "Closing Sharing releases its on-demand window owner")
    languageEditor.close()
    check(SettingsSharingController.errorText(ConfigurationShareError.fileTooLarge, chinese: true).contains("128 KiB"), "File-limit failure localized without decoder internals")
    print("PASS: native sharing Apply/Cancel/Undo callbacks, pending fences and English/Chinese screenshots")
}
