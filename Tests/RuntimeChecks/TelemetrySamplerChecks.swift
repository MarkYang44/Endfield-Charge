import AppKit
import ChargeCore

func runTelemetrySamplerChecks(defaults: UserDefaults) throws {
    let telemetrySettings = AppSettings(defaults: defaults)
    var sampler: TelemetryMonitor? = TelemetryMonitor(settings: telemetrySettings, battery: { telemetrySample.battery })
    weak var releasedSampler: TelemetryMonitor?
    releasedSampler = sampler
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
}
