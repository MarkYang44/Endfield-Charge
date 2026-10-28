import AppKit
import ChargeCore

func runHUDChecks(settings: AppSettings) throws {
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
}
