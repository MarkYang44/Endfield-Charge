import AppKit
import ChargeCore

func runSubprocessLifecycleChecks(settings: AppSettings) throws {
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
}
