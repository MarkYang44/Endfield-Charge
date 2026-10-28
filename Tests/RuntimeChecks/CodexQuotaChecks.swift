import AppKit
import ChargeCore

func runCodexQuotaChecks(defaults: UserDefaults) throws {
    let quota = CodexQuotaSnapshot(fiveHour: CodexQuotaWindow(usedPercent: 20, resetsAt: 1000), weekly: CodexQuotaWindow(usedPercent: 60, resetsAt: 2000))
    var now = 100.0
    var callbacks: [(CodexQuotaSnapshot?) -> Void] = []
    var cancellations = 0
    let reader = CodexQuotaReader(clock: { now }, fetch: { completion in
        callbacks.append(completion)
        return { cancellations += 1 }
    })
    check(reader.read(enabled: false) == nil && callbacks.isEmpty, "quota reader stays lazy")
    check(reader.read(enabled: true) == nil && callbacks.count == 1, "quota fetch starts asynchronously")
    _ = reader.read(enabled: true)
    check(callbacks.count == 1, "quota requests coalesce")
    callbacks[0](quota); spin(0.02)
    check(reader.read(enabled: true) == quota, "quota result is cached")
    _ = reader.read(enabled: false); now = 110
    check(reader.read(enabled: true) == quota && callbacks.count == 1, "carousel gap reuses cache")
    now = 401
    check(reader.read(enabled: true) == nil && callbacks.count == 2, "expired quota is unavailable while refreshing")
    _ = reader.read(enabled: false)
    check(cancellations == 1, "leaving quota cancels in-flight work")
    now = 462; _ = reader.read(enabled: true)
    check(callbacks.count == 2, "canceled child must finish cleanup before another launch")
    callbacks[1](quota); spin(0.02)
    now = 420
    check(reader.read(enabled: true) == nil && callbacks.count == 2, "old generation cannot publish and retry is bounded")
    now = 462; _ = reader.read(enabled: true)
    check(callbacks.count == 3, "failed or canceled read retries after minimum spacing")
    callbacks[2](nil); spin(0.02)
    check(reader.read(enabled: true) == nil, "unavailable refresh clears old quota")
    reader.reset()
    now = 600; _ = reader.read(enabled: true)
    callbacks[3](quota); spin(0.02)
    now = 1001
    _ = reader.read(enabled: true)
    check(callbacks.count == 5, "known reset triggers refresh")
    reader.reset(); callbacks[4](nil); spin(0.02)

    var resetNow = 500.0
    var resetCallbacks: [(CodexQuotaSnapshot?) -> Void] = []
    let resetReader = CodexQuotaReader(clock: { resetNow }, fetch: { completion in resetCallbacks.append(completion); return {} })
    let pastReset = CodexQuotaSnapshot(fiveHour: CodexQuotaWindow(usedPercent: 20, resetsAt: 400), weekly: quota.weekly)
    _ = resetReader.read(enabled: true); resetCallbacks[0](pastReset); spin(0.02)
    check(resetReader.read(enabled: true) == pastReset, "successful past-reset data remains visible, including the valid weekly window")
    resetNow = 561
    check(resetReader.read(enabled: true) == pastReset && resetCallbacks.count == 2, "known reset schedules a bounded refresh without hiding a recent successful response")
    resetCallbacks[1](nil); spin(0.02)
    check(resetReader.read(enabled: true) == nil, "failed reset refresh becomes unavailable")

    var owner: CodexQuotaReader? = CodexQuotaReader(clock: { now }, fetch: { callback in
        callbacks.append(callback); return { cancellations += 1 }
    })
    weak var weakOwner = owner
    defer { weakOwner = nil }
    _ = owner?.read(enabled: true); owner = nil
    check(weakOwner == nil && cancellations == 3, "pending fetch does not retain owner and teardown cancels")

    let settings = AppSettings(defaults: defaults, persistsChanges: false)
    settings.value = Preferences()
    let menu = StatusMenuController(settings: settings, target: NSObject(), entries: [("", "", nil, "")])
    let item = NSMenuItem(); item.representedObject = TelemetryMetric.codexFiveHourRemainingPercent.rawValue
    menu.selectCodexPreset(item)
    let selected = settings.value.selectedCapsuleID
    check(settings.value.capsuleProfiles.count == 6, "preset opt-in adds one custom profile")
    let preset = settings.value.capsuleProfiles.first { $0.id == selected }!
    check(preset.primaryMetric == .codexFiveHourRemainingPercent && preset.ringMetric == preset.primaryMetric && preset.referenceMaximum == 100, "preset selects correct ordinary quota profile")
    menu.selectCodexPreset(item)
    check(settings.value.capsuleProfiles.count == 6, "reselecting preset preserves custom profile")
    while settings.value.capsuleProfiles.count < 12 { settings.value.capsuleProfiles.append(.custom(title: "CUSTOM \(settings.value.capsuleProfiles.count)")) }
    item.representedObject = TelemetryMetric.codexWeeklyRemainingPercent.rawValue
    menu.selectCodexPreset(item)
    check(settings.value.capsuleProfiles.count == 12 && settings.value.selectedCapsuleID == selected, "preset at capacity does not drop profiles")

    settings.value = Preferences(); settings.value.language = "en"
    let editor = SettingsWindowController(settings: settings, selectedTab: 4, frame: nil, onPreview: { _ in }, onClose: { _,_ in })
    defer { editor.close() }
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    func activeSelector() -> NSPopUpButton {
        descendants(editor.window!.contentView!).compactMap { $0 as? NSPopUpButton }.first { $0.accessibilityLabel() == "Active capsule" }!
    }
    let selector = activeSelector()
    check(selector.itemTitles.contains("Codex · 5 hours") && selector.itemTitles.contains("Codex · Weekly"), "Settings Active capsule exposes both opt-in quota choices")
    selector.selectItem(withTitle: "Codex · Weekly"); editor.controlChanged(selector)
    check(settings.value.capsuleProfiles.count == 6 && settings.value.capsuleProfiles.last?.primaryMetric == .codexWeeklyRemainingPercent, "actual settings selector creates and selects weekly custom profile")
    let weeklyID = settings.value.selectedCapsuleID
    editor.setConfigurationPending(true)
    let pendingSelector = activeSelector(); pendingSelector.selectItem(withTitle: "Codex · 5 hours"); editor.controlChanged(pendingSelector)
    check(settings.value.selectedCapsuleID == weeklyID && settings.value.capsuleProfiles.count == 6, "pending transaction fence prevents preset mutation")
    editor.setConfigurationPending(false)
    editor.draftText["profile.\(weeklyID).color.0.threshold"] = "invalid"
    let fencedSelector = activeSelector(); fencedSelector.selectItem(withTitle: "Codex · 5 hours"); editor.controlChanged(fencedSelector)
    check(settings.value.selectedCapsuleID == weeklyID && settings.value.capsuleProfiles.count == 6, "unfinished color edit fence prevents preset mutation")
    editor.draftText.removeAll()
    while settings.value.capsuleProfiles.count < 12 { settings.value.capsuleProfiles.append(.custom(title: "CUSTOM \(settings.value.capsuleProfiles.count)")) }
    editor.buildPage()
    let fullSelector = activeSelector()
    check(fullSelector.item(withTitle: "Codex · 5 hours")?.isEnabled == false, "absent quota preset is disabled at capacity")
    check(fullSelector.item(withTitle: "Codex · Weekly")?.isEnabled == true, "existing quota preset remains selectable at capacity")
    fullSelector.selectItem(withTitle: "Codex · 5 hours"); editor.controlChanged(fullSelector)
    check(settings.value.capsuleProfiles.count == 12 && settings.value.selectedCapsuleID == weeklyID, "programmatic preset action also respects capacity")

    var preferences = Preferences()
    preferences.powerTelemetryEnabled = false; preferences.computeTelemetryEnabled = false; preferences.thermalTelemetryEnabled = false
    let absent = TelemetryDemand(preferences: preferences, panelVisible: true, capsuleMetrics: [])
    check(!absent.codexQuota, "terminal visibility alone does not request account limits")
    check(TelemetryDemand(preferences: preferences, panelVisible: false, capsuleMetrics: [.codexWeeklyRemainingPercent]).codexQuota, "visible quota requests limits")
    preferences.telemetryAlertRules = [TelemetryAlertRule(id: "quota", enabled: true, metric: .codexFiveHourRemainingPercent)]
    check(TelemetryDemand(preferences: preferences, panelVisible: false, capsuleMetrics: []).codexQuota, "enabled quota rule requests limits")
    preferences.telemetryAlertRules[0].enabled = false
    check(!TelemetryDemand(preferences: preferences, panelVisible: false, capsuleMetrics: []).codexQuota, "disabled quota rule stays lazy")

    var pending = false
    let slowReader = CodexQuotaReader(fetch: { _ in pending = true; return {} })
    settings.value = preferences
    settings.value.computeTelemetryEnabled = true
    let monitor = TelemetryMonitor(settings: settings, battery: { telemetrySample.battery }, codexReader: slowReader)
    monitor.start(); monitor.setCapsuleMetrics([.codexFiveHourRemainingPercent])
    awaitCondition({ monitor.latestSnapshot?.compute != nil }, "CPU collector publishes while quota fetch remains pending")
    check(pending && monitor.latestSnapshot?.codexQuota == nil, "pending quota does not block sampler")
    monitor.stop()

    var snapshot = telemetrySample; snapshot.codexQuota = quota
    let presentation = CapsulePresentation(profile: preset, snapshot: snapshot)
    check(presentation.primary == "80.0" && presentation.ringFraction == 0.8, "remaining percent drives left value and ring")
    check(presentation.quotaResetText(at: 100, chinese: false) == "15m", "middle countdown uses selected window")
    // Exercise the real subprocess protocol and cleanup using tiny disposable CLI fixtures.
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("endfield-quota-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    func fixture(_ name: String, _ body: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
    let protocolLog = folder.appendingPathComponent("methods")
    let cwdLog = folder.appendingPathComponent("cwd")
    let cli = try fixture("success", """
    pwd > '\(cwdLog.path)'
    read -r message
    printf '%s\\n' "$message" >> '\(protocolLog.path)'
    printf '%s\\n' '{"id":1,"result":{}}'
    read -r message
    printf '%s\\n' "$message" >> '\(protocolLog.path)'
    read -r message
    printf '%s\\n' "$message" >> '\(protocolLog.path)'
    printf '%s\\n' '{"id":2,"result":{"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":20,"windowDurationMins":300}}}}}'
    """)
    check(CodexQuotaRequest(executable: cli).read()?.fiveHour?.remainingPercent == 80, "native provider reads documented stdio result")
    let cwd = try String(contentsOf: cwdLog, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    check(URL(fileURLWithPath: cwd).resolvingSymlinksInPath() == FileManager.default.temporaryDirectory.resolvingSymlinksInPath(), "quota child uses neutral cwd rather than inherited project configuration")
    let messages = try String(contentsOf: protocolLog, encoding: .utf8).split(separator: "\n").map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
    check(messages.compactMap { $0["method"] as? String } == ["initialize", "initialized", "account/rateLimits/read"], "provider makes exactly the three read-only protocol calls")
    check(CodexQuotaRequest(executable: folder.appendingPathComponent("missing")).read() == nil, "missing executable stays unavailable without leaking pipe owners")
    let denied = try fixture("denied", "read -r message\nprintf '%s\\n' '{\"id\":1,\"error\":{\"code\":-1}}'")
    check(CodexQuotaRequest(executable: denied).read() == nil, "native provider handles unavailable login/protocol errors")
    let disconnected = try fixture("disconnected", "read -r message\nexec 0<&-\nprintf '%s\\n' '{\"id\":1,\"result\":{}}'")
    let previousSignal = signal(SIGPIPE, SIG_DFL)
    check(CodexQuotaRequest(executable: disconnected).read() == nil, "native provider tolerates peer closing between protocol messages")
    signal(SIGPIPE, previousSignal)
    let oversized = try fixture("oversized", "printf '%02048d' 0")
    check(CodexQuotaRequest(executable: oversized, maximumOutput: 1024).read() == nil, "native provider enforces cumulative output bound")
    let pidFile = folder.appendingPathComponent("pid")
    let slow = try fixture("slow", "echo $$ > '\(pidFile.path)'\nexec /bin/sleep 5")
    let before = ProcessInfo.processInfo.systemUptime
    check(CodexQuotaRequest(executable: slow, timeout: 1).read() == nil, "native provider times out")
    check(ProcessInfo.processInfo.systemUptime - before < 2, "timeout cleanup is bounded")
    check(FileManager.default.fileExists(atPath: pidFile.path), "timeout fixture had time to start before the deadline")
    let timedPID = Int32(try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
    check(kill(timedPID, 0) == -1 && errno == ESRCH, "timed-out child is reaped")
    try FileManager.default.removeItem(at: pidFile)
    let request = CodexQuotaRequest(executable: slow)
    var completed = false
    DispatchQueue.global().async {
        let result = request.read()
        DispatchQueue.main.async { check(result == nil, "canceled provider publishes no result"); completed = true }
    }
    awaitCondition({ FileManager.default.fileExists(atPath: pidFile.path) }, "owned test child starts")
    let canceledPID = Int32(try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
    request.cancel()
    awaitCondition({ completed }, "canceled native provider cleans up promptly")
    check(kill(canceledPID, 0) == -1 && errno == ESRCH, "canceled child is reaped")
    print("PASS: Codex quota presets, demand, cache, coalescing, cancellation, reset, teardown, nonblocking collector and bounded stdio cleanup")
}
