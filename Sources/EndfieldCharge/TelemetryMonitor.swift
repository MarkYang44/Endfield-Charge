import AppKit
import ChargeCore

final class TelemetryMonitor {
    private let settings: AppSettings
    private let battery: () -> BatterySnapshot
    private let reader = TelemetryReader()
    private let clock: () -> Double
    private let injectedRead: ((BatterySnapshot, TelemetryDemand) -> TelemetrySnapshot)?
    private var alerts = ThermalAlertState()
    private var rules = TelemetryRuleEvaluator()
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var running = false
    private var panelVisible = false
    private var capsuleMetrics: Set<TelemetryMetric> = []
    private var previousPreferences: Preferences?
    private(set) var latestSnapshot: TelemetrySnapshot?
    private(set) var samplingInterval: Double?
    var onSnapshot: ((TelemetrySnapshot) -> Void)?
    var onThermalAlert: ((ThermalLevel) -> Void)?
    var onRuleAlert: ((TelemetryAlertRule, TelemetrySnapshot) -> Void)?
    var onWake: (() -> Void)?
    var demand: TelemetryDemand {
        TelemetryDemand(preferences: settings.value, panelVisible: panelVisible, capsuleMetrics: capsuleMetrics)
    }

    init(settings: AppSettings, battery: @escaping () -> BatterySnapshot,
         clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         read: ((BatterySnapshot, TelemetryDemand) -> TelemetrySnapshot)? = nil) {
        self.settings = settings; self.battery = battery; self.clock = clock; injectedRead = read
    }
    func start() {
        guard !running else { return }
        running = true
        reader.reset(); alerts.reset(); rules.reset()
        previousPreferences = settings.value
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.resetAfterWake() }
        refresh(); scheduleTimer()
    }
    func resetAfterWake() {
        guard running else { return }
        reader.reset(); rules.reset(); capsuleMetrics = []
        onWake?()
        refresh(); scheduleTimer()
    }
    func preferencesChanged() {
        guard running else { return }
        if previousPreferences?.thermalTelemetryEnabled != settings.value.thermalTelemetryEnabled { alerts.reset() }
        previousPreferences = settings.value
        capsuleMetrics = []
        refresh(); scheduleTimer()
    }
    func setPanelVisible(_ visible: Bool) {
        guard visible != panelVisible else { return }
        panelVisible = visible
        guard running else { return }
        refresh(); scheduleTimer()
    }
    func setCapsuleMetrics(_ metrics: Set<TelemetryMetric>) {
        guard metrics != capsuleMetrics else { return }
        capsuleMetrics = metrics
        guard running else { return }
        refresh(); scheduleTimer()
    }
    func stop() {
        running = false
        timer?.invalidate(); timer = nil; samplingInterval = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        reader.reset(); alerts.reset(); rules.reset(); previousPreferences = nil
        capsuleMetrics = []; latestSnapshot = nil
    }
    private func scheduleTimer() {
        timer?.invalidate(); timer = nil; samplingInterval = nil
        guard running, demand.hasWork else { return }
        let interval = demand.highFrequency ? 2.0 : 30.0
        samplingInterval = interval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = demand.highFrequency ? 0.3 : 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    func refresh() {
        guard running else { return }
        let preferences = settings.value, demand = demand
        var snapshot = injectedRead?(battery(), demand) ?? reader.read(battery: battery(), powerEnabled: demand.power,
            computeEnabled: demand.compute, thermalEnabled: demand.thermal, networkEnabled: demand.network, storageEnabled: demand.storage)
        // Filtering is also enforced at the routing boundary, including battery-derived metrics.
        if !demand.power { snapshot.power = nil }
        if !demand.compute { snapshot.compute = nil }
        if !demand.thermal { snapshot.thermal = nil }
        if !demand.network { snapshot.network = nil }
        if !demand.storage { snapshot.storage = nil }
        latestSnapshot = snapshot
        onSnapshot?(snapshot)
        if let thermal = snapshot.thermal, alerts.shouldAlert(thermal, enabled: preferences.thermalAlert) { onThermalAlert?(thermal) }
        var values: [TelemetryMetric: Double] = [:]
        for metric in TelemetryMetric.allCases {
            if let value = metric.value(in: snapshot) { values[metric] = value }
        }
        let fired = rules.evaluate(rules: preferences.telemetryAlertRules, values: values, at: clock())
        // All simultaneous IDs have been consumed by the evaluator; present one bounded event.
        if let id = fired.first, let rule = preferences.telemetryAlertRules.first(where: { $0.id == id }) { onRuleAlert?(rule, snapshot) }
    }
    deinit {
        timer?.invalidate()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
}
