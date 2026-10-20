import AppKit
import ChargeCore

func runPlaybackChecks() {
    func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError("Playback check failed: \(message)") }
    }
    func spin(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
    func view() -> HUDView? { NSApplication.shared.windows.first { $0.isVisible && $0.contentView is HUDView }?.contentView as? HUDView }
    let domain = "endfield-playback-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let settings = AppSettings(defaults: defaults)
    settings.value = Preferences()
    settings.value.playback.persistent = true
    settings.value.duration = 3
    settings.value.capsuleProfiles[0].colorConditions = [CapsuleColorCondition(metric: .networkDownloadBytesPerSecond,
        comparison: .above, threshold: 10, accent: .amber)]
    var now = 1.0
    var sample = TelemetrySnapshot(sampledAt: now, battery: BatterySnapshot(percent: 65), power: nil,
        compute: nil, thermal: .nominal, network: NetworkTelemetry(downloadBytesPerSecond: 100,
        uploadBytesPerSecond: nil, receivedBytes: 0, sentBytes: 0, interfaces: ["en0"]))
    let hud = HUDController(settings: settings, reduceMotion: { false })
    let playback = CapsulePlaybackController(settings: settings, hud: hud, clock: { now })
    var demand: Set<TelemetryMetric> = []
    playback.onCapsuleDemand = { demand = $0 }
    playback.preferencesChanged(); check(view() == nil, "Persistent start waits for actual snapshot")
    playback.updateTelemetry(sample)
    check(view()?.capsule == nil && view()?.snapshot.percent == 65, "Colored builtin battery preserves battery geometry")
    check(demand.contains(.batteryPercent) && demand.contains(.networkDownloadBytesPerSecond), "Palette and battery dependencies demand live data")
    check(view()?.accentOverride == .amber, "Palette resolves from actual sample")
    spin(2.7)
    check(!hud.hasAnimationTimer && playback.nextDeadline == nil && view()?.compactHold == true,
        "Single persistent profile has neither animation nor rotation timer after settling")
    playback.updateBattery(BatterySnapshot(percent: 66))
    check(view()?.snapshot.percent == 66, "Actual new power snapshot updates held battery")
    sample.battery = BatterySnapshot(percent: 10); playback.updateTelemetry(sample)
    check(view()?.resolvedAccent == .red, "True low battery overrides ordinary palette")
    playback.setHidden(true)
    check(view() == nil && demand.isEmpty, "Menu hide releases visible demand")
    playback.showPower(BatterySnapshot(percent: 70))
    playback.previewProfile(id: CapsuleProfile.cpuID)
    check(view()?.capsule == nil && view()?.snapshot.percent == 70, "Manual preview waits behind real power")
    spin(3.2)
    check(view()?.capsule?.profile.id == CapsuleProfile.cpuID, "Waiting preview starts when power completes")
    spin(3.2); check(view() == nil, "Hidden ambient stays hidden after explicit content")
    playback.setHidden(false); check(view() != nil, "Resume restores ambient")
    playback.suspend(); check(view() == nil && demand.isEmpty, "Sleep stops presentation and demand")
    playback.wake(); check(view() == nil, "Wake does not replay stale snapshot")
    sample.battery = BatterySnapshot(percent: 82); playback.updateTelemetry(sample)
    check(view()?.snapshot.percent == 82, "First fresh sample restores held battery")
    settings.value.networkTelemetryEnabled = false; playback.preferencesChanged()
    check(view()?.accentOverride == .theme, "Disabled palette source never uses cached data")
    playback.stop(); check(view() == nil && demand.isEmpty, "Stop releases one HUD owner")

    let reducedHUD = HUDController(settings: settings, reduceMotion: { true })
    let reduced = CapsulePlaybackController(settings: settings, hud: reducedHUD, clock: { now })
    settings.value.playback.rotationEnabled = true
    settings.value.playback.profileIDs = [CapsuleProfile.cpuID, CapsuleProfile.memoryID]
    settings.value.playback.intervalSeconds = 10
    reduced.preferencesChanged(); reduced.updateTelemetry(sample)
    check(!reducedHUD.hasAnimationTimer && view()?.compactHold == true && reduced.nextDeadline == 11,
        "Reduce Motion goes directly compact and keeps configured dwell")
    now = 11; reduced.advance()
    check(view()?.capsule?.profile.id == CapsuleProfile.memoryID && !reducedHUD.hasAnimationTimer && reduced.nextDeadline == 21,
        "Reduced rotation switches directly without reducing the next dwell")
    reduced.stop()

    let synchronizedSettings = AppSettings(defaults: defaults)
    synchronizedSettings.value = Preferences()
    synchronizedSettings.value.playback.persistent = true
    synchronizedSettings.value.powerTelemetryEnabled = false
    synchronizedSettings.value.computeTelemetryEnabled = false
    synchronizedSettings.value.thermalTelemetryEnabled = false
    let synchronizedHUD = HUDController(settings: synchronizedSettings, reduceMotion: { true })
    let synchronized = CapsulePlaybackController(settings: synchronizedSettings, hud: synchronizedHUD)
    let synchronousSampler = TelemetryMonitor(settings: synchronizedSettings, battery: { sample.battery },
        read: { battery, _ in TelemetrySnapshot(sampledAt: 1, battery: battery, power: nil, compute: nil, thermal: nil) })
    synchronized.onCapsuleDemand = { synchronousSampler.setCapsuleMetrics($0) }
    synchronousSampler.onSnapshot = { synchronized.updateTelemetry($0) }
    synchronousSampler.onWake = { synchronized.wake() }
    synchronousSampler.onSleep = { synchronized.suspend() }
    synchronousSampler.start(); synchronized.preferencesChanged()
    check(view() != nil && synchronousSampler.samplingInterval == 2, "Synchronous demand publication retains current persistent HUD")
    synchronizedSettings.value.scale = 0.9
    synchronousSampler.preferencesChanged(); synchronized.preferencesChanged()
    check(view() != nil && synchronousSampler.samplingInterval == 2, "Preferences invalidate sampler before reapplying visible demand")
    synchronousSampler.suspendForSleep(); synchronousSampler.resetAfterWake()
    check(view()?.snapshot == sample.battery && synchronousSampler.samplingInterval == 2,
        "Fresh wake with synchronous sampler restores one surface and active cadence")
    synchronized.setHidden(true)
    check(view() == nil && synchronousSampler.samplingInterval == nil, "Hidden battery without independent modules stops sampler timer")
    synchronized.stop(); synchronousSampler.stop()

    let transitionSettings = AppSettings(defaults: defaults)
    transitionSettings.value = Preferences()
    transitionSettings.value.playback = CapsulePlayback(persistent: true, rotationEnabled: true,
        profileIDs: [CapsuleProfile.cpuID, CapsuleProfile.memoryID], intervalSeconds: 10)
    now = 0
    let transitionHUD = HUDController(settings: transitionSettings, reduceMotion: { false })
    let transition = CapsulePlaybackController(settings: transitionSettings, hud: transitionHUD, clock: { now })
    transition.preferencesChanged(); transition.updateTelemetry(sample); spin(2.7)
    check(!transitionHUD.hasAnimationTimer, "Persistent introduction stops after finite animation")
    now = 10; transition.advance()
    check(view()?.capsule?.profile.id == CapsuleProfile.cpuID, "Compact transition first retracts outgoing profile")
    spin(0.4)
    check(view()?.capsule?.profile.id == CapsuleProfile.memoryID && !transitionHUD.hasAnimationTimer,
        "Compact transition expands incoming profile once and stops")
    transition.stop()

    let finiteSettings = AppSettings(defaults: defaults)
    finiteSettings.value = Preferences()
    finiteSettings.value.duration = 3
    finiteSettings.value.selectedCapsuleID = CapsuleProfile.cpuID
    finiteSettings.value.playback = CapsulePlayback(rotationEnabled: true,
        profileIDs: [CapsuleProfile.cpuID, CapsuleProfile.memoryID], intervalSeconds: 10)
    let finiteHUD = HUDController(settings: finiteSettings, reduceMotion: { true })
    let finite = CapsulePlaybackController(settings: finiteSettings, hud: finiteHUD, clock: { now })
    finite.onCapsuleDemand = { demand = $0 }
    finite.preferencesChanged(); finite.updateTelemetry(sample); finite.previewSelected()
    check(view()?.capsule?.profile.id == CapsuleProfile.cpuID, "Finite selected-first carousel starts")
    finite.setHidden(true)
    check(view() == nil && demand.isEmpty, "Hide stops first finite item and releases demand")
    finite.setHidden(false)
    check(view()?.capsule?.profile.id == CapsuleProfile.cpuID, "Resume restarts paused finite item")
    finite.showPower(BatterySnapshot(percent: 75)); finite.previewSelected(); finite.setHidden(true)
    check(view()?.snapshot.percent == 75, "Hide preserves independent real power presentation")
    spin(3.2)
    check(view() == nil && demand.isEmpty, "Pending finite carousel stays paused after power completes")
    finite.setHidden(false)
    check(view()?.capsule?.profile.id == CapsuleProfile.cpuID, "Resume restores carousel queued before hide")
    finite.suspend(); finite.wake(); finite.setHidden(true); finite.setHidden(false)
    check(view() == nil && demand.isEmpty, "Finite carousel waits for fresh wake data even through menu resume")
    finite.updateTelemetry(sample)
    check(view()?.capsule?.profile.id == CapsuleProfile.cpuID, "Fresh wake snapshot resumes finite carousel")
    finite.stop()

    // Actual sampler owns rule baselines, typed labels, duplicate suppression and sleep gates.
    let monitorSettings = AppSettings(defaults: defaults)
    monitorSettings.value = Preferences()
    let thermalRule = TelemetryAlertRule(id: "thermal", name: "Thermal change", enabled: true,
        holdSeconds: 0, cooldownSeconds: 10, condition: .stateChange, source: .thermal)
    let memoryRule = TelemetryAlertRule(id: "memory", name: "Memory change", enabled: true,
        holdSeconds: 0, cooldownSeconds: 10, condition: .stateChange, source: .memoryPressure)
    let delayedThermal = TelemetryAlertRule(id: "delayed-thermal", name: "Delayed thermal", enabled: true,
        holdSeconds: 10, cooldownSeconds: 10, condition: .stateChange, source: .thermal, targetState: .thermal(.serious))
    monitorSettings.value.telemetryAlertRules = [thermalRule, memoryRule, delayedThermal]
    monitorSettings.value.thermalAlert = true
    var thermal = ThermalLevel.nominal, pressure = MemoryPressureLevel.normal
    let monitor = TelemetryMonitor(settings: monitorSettings, battery: { sample.battery }, clock: { now }, read: { battery, _ in
        TelemetrySnapshot(sampledAt: now, battery: battery, power: nil,
            compute: ComputeTelemetry(cpuFraction: 0, memoryUsedBytes: 0, memoryTotalBytes: 1,
                compressedBytes: nil, swapUsedBytes: nil, pressure: pressure), thermal: thermal)
    })
    var builtin: [ThermalLevel] = [], rules: [String] = []
    monitor.onThermalAlert = { builtin.append($0) }; monitor.onRuleAlert = { rule, _ in rules.append(rule.id) }
    monitor.start(); check(rules.isEmpty && builtin.isEmpty, "First state snapshot quietly establishes baseline")
    now += 1; thermal = .serious; pressure = .warning; monitor.refresh()
    check(builtin == [.serious] && rules == ["memory"], "Same thermal transition deduplicates without suppressing unrelated memory alert")
    now += 10; monitor.refresh()
    check(builtin == [.serious] && rules == ["memory"], "Delayed state rule for the same thermal transition remains deduplicated")
    let warning = CapsulePresentation(rule: memoryRule, snapshot: monitor.latestSnapshot!, chinese: false)
    check(warning.primary == "Warning" && warning.primaryUnit.isEmpty && warning.accent == .amber,
        "Memory warning uses typed text and amber, not the compatibility numeric metric")
    let chinese = CapsulePresentation(rule: memoryRule, snapshot: monitor.latestSnapshot!, chinese: true)
    check(chinese.primary == "警告", "State label localizes")
    now += 11; thermal = .nominal; pressure = .normal; monitor.refresh()
    check(rules.suffix(2) == ["thermal", "memory"], "Independent simultaneous rules enter delivery queue in configuration order")
    let normal = CapsulePresentation(rule: memoryRule, snapshot: monitor.latestSnapshot!, chinese: false)
    check(normal.accent == .theme && normal.primary == "Normal", "State recovery uses theme")
    monitor.suspendForSleep(); thermal = .critical; pressure = .critical; now += 100
    monitor.refresh(); check(monitor.samplingInterval == nil, "Sleep prevents collection and timer")
    monitor.resetAfterWake()
    check(builtin == [.serious] && rules.count == 3, "Wake resets both builtin and custom baseline without stale alerts")
    monitor.stop()
    runPlaybackReviewChecks()
    print("PASS: playback coordinator, static hold, priority, live battery/palette, reduced motion, sleep and typed state alerts")
}

func runPlaybackReviewChecks() {
    var failures: [String] = []
    func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { failures.append(message); print("FAIL: \(message)") }
    }
    func spin(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
    func visibleView() -> HUDView? { NSApplication.shared.windows.first { $0.isVisible && $0.contentView is HUDView }?.contentView as? HUDView }
    func png(_ view: HUDView) -> Data {
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])!
    }
    let domain = "endfield-playback-review.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let settings = AppSettings(defaults: defaults)
    let battery = BatterySnapshot(percent: 67)
    var sample = TelemetrySnapshot(sampledAt: 1, battery: battery, power: nil,
        compute: ComputeTelemetry(cpuFraction: 0.8, memoryUsedBytes: 1, memoryTotalBytes: 2,
            compressedBytes: nil, swapUsedBytes: nil, pressure: .warning), thermal: .serious,
        network: NetworkTelemetry(downloadBytesPerSecond: 100, uploadBytesPerSecond: 0,
            receivedBytes: 0, sentBytes: 0, interfaces: ["en0"]))
    let network = TelemetryAlertRule(id: "network-disabled", enabled: true, metric: .networkDownloadBytesPerSecond)
    let cpu = TelemetryAlertRule(id: "cpu-independent", enabled: true)
    let batteryRule = TelemetryAlertRule(id: "battery-independent", enabled: true, metric: .batteryPercent)
    let thermal = TelemetryAlertRule(id: "thermal-disabled", enabled: true, condition: .stateChange, source: .thermal)
    func reset() {
        settings.value = Preferences(); settings.value.duration = 3
        settings.value.telemetryAlertRules = [network, cpu, batteryRule, thermal]
    }
    reset()
    let hud = HUDController(settings: settings, reduceMotion: { true })
    let playback = CapsulePlaybackController(settings: settings, hud: hud)
    playback.preferencesChanged(); playback.updateTelemetry(sample)
    playback.showPower(battery); playback.showRule(network, snapshot: sample); playback.showRule(cpu, snapshot: sample)
    settings.value.networkTelemetryEnabled = false; playback.preferencesChanged()
    check(visibleView()?.kind == .power && visibleView()?.capsule == nil, "Disabling queued source preserves real power")
    spin(3.15)
    check(visibleView()?.capsule?.profile.id == "rule.cpu-independent", "Disabled queued network rule is removed while unrelated CPU alert survives")
    playback.stop()

    reset()
    let activeHUD = HUDController(settings: settings, reduceMotion: { true })
    let active = CapsulePlaybackController(settings: settings, hud: activeHUD)
    active.preferencesChanged(); active.updateTelemetry(sample); active.showRule(network, snapshot: sample)
    settings.value.networkTelemetryEnabled = false; active.preferencesChanged()
    check(visibleView() == nil, "Active rule is canceled when its source module is disabled")
    settings.value.thermalTelemetryEnabled = true; active.preferencesChanged(); active.showRule(thermal, snapshot: sample)
    settings.value.thermalTelemetryEnabled = false; active.preferencesChanged()
    check(visibleView() == nil, "Active typed thermal state rule is canceled with thermal module")
    active.stop()

    reset()
    let atomicHUD = HUDController(settings: settings, reduceMotion: { true })
    let atomic = CapsulePlaybackController(settings: settings, hud: atomicHUD)
    atomic.preferencesChanged(); atomic.updateTelemetry(sample)
    atomic.showRule(cpu, snapshot: sample); atomic.showRule(network, snapshot: sample); atomic.showRule(batteryRule, snapshot: sample)
    var changedDemands: [Set<TelemetryMetric>] = []
    atomic.onCapsuleDemand = { changedDemands.append($0) }
    settings.value.telemetryAlertRules.removeAll { $0.id == cpu.id }; settings.value.networkTelemetryEnabled = false
    atomic.preferencesChanged()
    check(visibleView()?.capsule?.profile.id == "rule.battery-independent", "Combined rule deletion and module disable keeps unrelated queued alert")
    check(!changedDemands.contains { $0.contains(.networkDownloadBytesPerSecond) }, "Configuration invalidation never transiently presents stale-source queue entries")
    atomic.stop()

    let cases: [(HUDKind, (inout Preferences) -> Void)] = [
        (.lowBattery, { $0.lowBatteryAlert = false }), (.fullyCharged, { $0.fullBatteryAlert = false }),
        (.lowPowerEnabled, { $0.lowPowerAlert = false }), (.lowPowerDisabled, { $0.lowPowerAlert = false }),
        (.thermalWarning, { $0.thermalAlert = false }), (.thermalCritical, { $0.thermalTelemetryEnabled = false })
    ]
    for (kind, disable) in cases {
        reset()
        let caseHUD = HUDController(settings: settings, reduceMotion: { true })
        let controller = CapsulePlaybackController(settings: settings, hud: caseHUD)
        controller.preferencesChanged(); controller.showPower(battery); controller.showAlert(battery, kind: kind)
        controller.previewBattery(BatterySnapshot(percent: 31)); disable(&settings.value); controller.preferencesChanged()
        check(visibleView()?.kind == .power && visibleView()?.snapshot.percent == 67, "Alert disable preserves actual power for \(kind)")
        spin(3.15)
        check(visibleView()?.kind == .power && visibleView()?.snapshot.percent == 31, "Disabled builtin \(kind) is discarded and manual demo survives")
        controller.stop()
    }
    reset()
    let currentHUD = HUDController(settings: settings, reduceMotion: { true })
    let current = CapsulePlaybackController(settings: settings, hud: currentHUD)
    current.preferencesChanged(); current.showAlert(battery, kind: .lowPowerEnabled)
    settings.value.lowPowerAlert = false; current.preferencesChanged()
    check(visibleView() == nil, "Already active builtin alert cancels with its switch")
    current.stop()

    // Compare the ACTUAL controller-produced output against the original reduced-motion alert path.
    reset()
    let renderHUD = HUDController(settings: settings, reduceMotion: { true })
    var completions = 0
    for kind in [HUDKind.thermalCritical, .lowPowerEnabled] {
        renderHUD.render(battery: battery, kind: kind) { completions += 1 }
        let actual = visibleView()!
        check(actual.frameOverride?.titleOpacity == 1 && actual.frameOverride?.numbersOpacity == 0,
            "Reduced-motion \(kind) frame retains identifying title and omits ordinary battery numbers")
        let actualPNG = png(actual)
        let savedFrame = actual.frameOverride, savedElapsed = actual.elapsed
        // Use the same attached view/backing color space for the pre-override reduced-motion reference.
        actual.frameOverride = nil; actual.elapsed = 0.15
        let referencePNG = png(actual)
        actual.frameOverride = savedFrame; actual.elapsed = savedElapsed
        check(actualPNG == referencePNG, "Native reduced-motion \(kind) pixels match identifying-title reference")
        if kind == .lowPowerEnabled {
            spin(0.2)
            check(visibleView() != nil && completions == 0, "Reduced-motion builtin keeps full configured dwell")
            spin(3.0)
            check(visibleView() == nil && completions == 1, "Reduced-motion builtin completes at full dwell")
        } else { renderHUD.dismiss() }
    }
    renderHUD.dismiss()

    let severityCases: [(ThermalLevel, CapsuleAccent)] = [(.nominal, .theme), (.fair, .amber), (.serious, .red), (.critical, .red)]
    for (level, accent) in severityCases {
        sample.thermal = level
        check(CapsulePresentation(rule: thermal, snapshot: sample, chinese: false).accent == accent,
            "Typed thermal \(level) uses severity \(accent)")
    }
    let memory = TelemetryAlertRule(id: "memory-severity", enabled: true, condition: .stateChange, source: .memoryPressure)
    for (pressure, accent) in [(MemoryPressureLevel.normal, CapsuleAccent.theme), (.warning, .amber), (.critical, .red)] {
        sample.compute?.pressure = pressure
        check(CapsulePresentation(rule: memory, snapshot: sample, chinese: false).accent == accent,
            "Typed memory \(pressure) retains severity \(accent)")
    }
    if !failures.isEmpty { fatalError("Playback review regressions failed: \(failures.count)\n" + failures.joined(separator: "\n")) }
}
