import AppKit
import ChargeCore

func runHUDChecks(settings: AppSettings) throws {
    runPlaybackChecks()
    let saved = settings.value
    defer { settings.value = saved }
    settings.value = Preferences()
    settings.value.duration = 4

    let hud = HUDController(settings: settings)
    let playback = CapsulePlaybackController(settings: settings, hud: hud)
    playback.preferencesChanged()
    let initial = BatterySnapshot(hasBattery: true, percent: 76, externalPower: true, isCharging: true)
    let alert = BatterySnapshot(hasBattery: true, percent: 19)
    func visibleHUD() -> HUDView? {
        autoreleasepool {
            app.windows.first(where: { $0.isVisible && $0.contentView is HUDView })?.contentView as? HUDView
        }
    }
    weak var releasedHUD: HUDView?
    autoreleasepool {
    playback.showPower(initial)
    spin(2.75)
    check(visibleHUD()?.kind == .power, "Initial HUD reaches static hold")
    playback.showAlert(alert, kind: .lowBattery)
    spin(0.1)
    check(visibleHUD()?.kind == .power, "Alert queues instead of interrupting the static hold")
    spin(1.3)
    check(visibleHUD()?.kind == .lowBattery, "Queued alert plays after the first HUD closes")
    let interrupted = BatterySnapshot(hasBattery: true, percent: 50)
    playback.previewBattery(interrupted)
    check(visibleHUD()?.kind == .lowBattery, "Preview waits behind the active alert")
    spin(4.1)
    check(visibleHUD()?.snapshot.percent == 50, "Queued preview starts after the higher-priority alert")
    releasedHUD = visibleHUD()
    spin(4.2)
    check(visibleHUD() == nil, "Finished HUD is no longer visible")
    }
    check(releasedHUD == nil, "Finished HUD view/backing owner deallocates")
    print("PASS: static-hold queue, production priority and HUD release")

    let networkProfile = CapsuleProfile.defaults.first { $0.id == CapsuleProfile.networkID }!
    var capsuleDemand: Set<TelemetryMetric> = []
    playback.onCapsuleDemand = { capsuleDemand = $0 }
    playback.updateTelemetry(telemetrySample)
    playback.previewProfile(id: networkProfile.id)
    check(capsuleDemand.contains(.networkDownloadBytesPerSecond), "Profile requests metric while visible")
    check(visibleHUD()?.capsule?.primary == "—" && visibleHUD()?.capsule?.ringFraction == nil,
        "Missing profile sample keeps unknown text and ring")
    var networkSample = telemetrySample
    networkSample.network = NetworkTelemetry(downloadBytesPerSecond: 1_048_576, uploadBytesPerSecond: 0,
        receivedBytes: 0, sentBytes: 0, interfaces: ["en0"])
    playback.updateTelemetry(networkSample)
    check(visibleHUD()?.capsule?.primary == "1.0", "Resident samples update the actual visible payload during hold")
    playback.showAlert(alert, kind: .lowBattery)
    playback.showPower(initial)
    check(capsuleDemand.isEmpty && visibleHUD()?.capsule == nil, "Power interruption releases visible profile demand")
    playback.suspend()
    check(visibleHUD() == nil && capsuleDemand.isEmpty, "Dismissal releases profile view and demand immediately")
    playback.wake()
    let customRule = TelemetryAlertRule(id: "queued-native-rule", name: "Storage warning", enabled: true,
        metric: .storageAvailableBytes, comparison: .below, threshold: 1_073_741_824)
    settings.value.telemetryAlertRules = [customRule]
    playback.preferencesChanged()
    playback.showRule(customRule, snapshot: networkSample)
    check(visibleHUD()?.capsule?.alert == true, "Generic rule uses the capsule alert presentation")
    settings.value.telemetryAlertRules = []
    playback.preferencesChanged()
    check(visibleHUD() == nil && capsuleDemand.isEmpty, "Deleting a rule releases active alert and demand")
    settings.value.networkTelemetryEnabled = false
    playback.preferencesChanged()
    playback.updateTelemetry(networkSample)
    playback.previewProfile(id: networkProfile.id)
    check(visibleHUD()?.capsule?.primary == "—", "Disabled network renders unknown despite cached resident values")
    playback.suspend()
    playback.wake()
    settings.value.networkTelemetryEnabled = true
    playback.preferencesChanged()
    var replayAtRelease = false
    playback.onCapsuleDemand = { [weak playback] metrics in
        capsuleDemand = metrics
        if metrics.isEmpty && replayAtRelease { replayAtRelease = false; playback?.showPower(initial) }
    }
    playback.updateTelemetry(networkSample)
    playback.previewProfile(id: networkProfile.id)
    replayAtRelease = true
    spin(4.15)
    check(visibleHUD() != nil, "A synchronous fresh event during demand release retains its new HUD owner")
    playback.suspend()
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

    // Renderer edge: callbacks may synchronously create the next surface without a coordinator.
    let reentrantHUD = HUDController(settings: settings)
    var renderAtRelease = false
    reentrantHUD.onCapsuleDemand = { [weak reentrantHUD] metrics in
        if metrics.isEmpty && renderAtRelease {
            renderAtRelease = false
            reentrantHUD?.render(battery: initial, kind: .power) {}
        }
    }
    reentrantHUD.render(profile: networkProfile, snapshot: networkSample, holding: false,
        compactTransition: false) {}
    renderAtRelease = true
    spin(4.15)
    check(visibleHUD()?.snapshot == initial && visibleHUD()?.capsule == nil,
        "Renderer demand-release reentrancy retains the newly created native owner")
    reentrantHUD.dismiss()
    var completedAfterTeardown = false
    reentrantHUD.render(battery: alert, kind: .lowBattery) { [weak reentrantHUD] in
        completedAfterTeardown = visibleHUD() == nil
        reentrantHUD?.render(battery: initial, kind: .power) {}
    }
    spin(4.15)
    check(completedAfterTeardown && visibleHUD()?.snapshot == initial,
        "Renderer finishes teardown before completion creates a fresh native owner")
    reentrantHUD.dismiss()

    playback.wake()
    settings.value.duration = 3
    for _ in 0..<2 {
        autoreleasepool { playback.showPower(initial) }
        spin(3.2)
        check(visibleHUD() == nil, "Repeated HUD has no lingering visible panel")
    }
    weak var releasedActiveHUD: HUDView?
    weak var releasedRenderer: HUDController?
    weak var releasedPlayback: CapsulePlaybackController?
    var activeDemand: Set<TelemetryMetric> = []
    autoreleasepool {
        var transient: HUDController? = HUDController(settings: settings)
        var owner: CapsulePlaybackController? = CapsulePlaybackController(settings: settings, hud: transient!)
        releasedRenderer = transient; releasedPlayback = owner
        owner?.onCapsuleDemand = { activeDemand = $0 }
        owner?.preferencesChanged(); owner?.updateTelemetry(networkSample)
        owner?.previewProfile(id: networkProfile.id)
        releasedActiveHUD = visibleHUD()
        check(releasedActiveHUD != nil && activeDemand.contains(.networkDownloadBytesPerSecond),
            "Transient playback owns a visible profile and active demand before release")
        transient = nil
        owner = nil
    }
    spin(0.1)
    check(releasedActiveHUD == nil && releasedRenderer == nil && releasedPlayback == nil && activeDemand.isEmpty,
        "Releasing active playback owner clears renderer, surface and demand")
    playback.stop()
    print("PASS: repeated animation lifecycle")
}
