import AppKit
import ChargeCore

final class TelemetryMonitor {
    private let settings: AppSettings
    private let codexReader: CodexQuotaReader
    private let battery: () -> BatterySnapshot
    private struct DisabledEpochs {
        var power: UInt64 = 0
        var compute: UInt64 = 0
        var network: UInt64 = 0
    }
    private typealias AsyncRead = (BatterySnapshot, TelemetryDemand, () -> TelemetrySnapshot) -> TelemetrySnapshot
    private struct Request {
        let generation: UInt64
        let resetEpoch: UInt64
        let disabledEpochs: DisabledEpochs
        let battery: BatterySnapshot
        let preferences: Preferences
        let demand: TelemetryDemand
        let codexQuota: CodexQuotaSnapshot?
    }
    /// Reader state is owned exclusively by this serial worker, including resets.
    private final class Collector {
        let queue = DispatchQueue(label: "com.markyang.endfieldcharge.telemetry", autoreleaseFrequency: .workItem)
        private var reader: TelemetryReader?
        private var resetEpoch: UInt64?
        private var disabledEpochs = DisabledEpochs()
        func read(_ request: Request, using injected: AsyncRead?) -> TelemetrySnapshot {
            if resetEpoch != request.resetEpoch { reset(); resetEpoch = request.resetEpoch }
            else {
                reader?.resetDisabled(power: disabledEpochs.power != request.disabledEpochs.power,
                    compute: disabledEpochs.compute != request.disabledEpochs.compute,
                    network: disabledEpochs.network != request.disabledEpochs.network)
            }
            disabledEpochs = request.disabledEpochs
            if reader == nil { reader = TelemetryReader() }
            let collect = { [self] in
                reader!.read(battery: request.battery, powerEnabled: request.demand.power,
                    computeEnabled: request.demand.compute, thermalEnabled: request.demand.thermal,
                    networkEnabled: request.demand.network, storageEnabled: request.demand.storage)
            }
            return injected?(request.battery, request.demand, collect) ?? collect()
        }
        func reset() { reader?.reset(); resetEpoch = nil }
    }
    private let collector = Collector()
    private let asynchronousRead: AsyncRead?
    private var inFlight = false
    private var pendingRequest: Request?
    private var generation: UInt64 = 0
    private var resetEpoch: UInt64 = 0
    private var disabledEpochs = DisabledEpochs()
    private var previousDemand: TelemetryDemand?
    private let clock: () -> Double
    private let injectedRead: ((BatterySnapshot, TelemetryDemand) -> TelemetrySnapshot)?
    private var alerts = ThermalAlertState()
    private var rules = TelemetryRuleEvaluator()
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var sleeping = false
    private var observedThermal: ThermalLevel?
    private var builtinPresentedForTransition = false
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
    var onSleep: (() -> Void)?
    var demand: TelemetryDemand {
        TelemetryDemand(preferences: settings.value, panelVisible: panelVisible, capsuleMetrics: capsuleMetrics)
    }

    init(settings: AppSettings, battery: @escaping () -> BatterySnapshot,
         clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         read: ((BatterySnapshot, TelemetryDemand) -> TelemetrySnapshot)? = nil,
         codexReader: CodexQuotaReader = CodexQuotaReader(),
         asyncRead: ((BatterySnapshot, TelemetryDemand, () -> TelemetrySnapshot) -> TelemetrySnapshot)? = nil) {
        self.codexReader = codexReader
        self.settings = settings; self.battery = battery; self.clock = clock; injectedRead = read; asynchronousRead = asyncRead
    }
    func start() {
        guard !running else { return }
        running = true
        invalidate(resetReader: true); alerts.reset(); rules.reset()
        previousPreferences = settings.value
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.resetAfterWake() }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.suspendForSleep() }
        refresh(); scheduleTimer()
    }
    func suspendForSleep() {
        guard running else { return }
        sleeping = true
        invalidate(resetReader: true); rules.reset(); alerts.reset()
        observedThermal = nil; builtinPresentedForTransition = false
        capsuleMetrics = []; latestSnapshot = nil
        timer?.invalidate(); timer = nil; samplingInterval = nil
        onSleep?()
    }
    func resetAfterWake() {
        guard running else { return }
        sleeping = false
        invalidate(resetReader: true); rules.reset(); alerts.reset(); capsuleMetrics = []
        observedThermal = nil; builtinPresentedForTransition = false; latestSnapshot = nil
        onWake?()
        refresh(); scheduleTimer()
    }
    func preferencesChanged() {
        guard running else { return }
        if previousPreferences?.thermalTelemetryEnabled != settings.value.thermalTelemetryEnabled {
            alerts.reset(); observedThermal = nil; builtinPresentedForTransition = false
        }
        previousPreferences = settings.value
        invalidate()
        capsuleMetrics = []
        // A preference change can remove data while a collector is still blocked.
        // Clear pending excursions now without bypassing existing cooldown state.
        _ = rules.evaluate(rules: settings.value.telemetryAlertRules, values: [:], at: clock())
        refresh(); scheduleTimer()
    }
    func setPanelVisible(_ visible: Bool) {
        guard visible != panelVisible else { return }
        panelVisible = visible
        guard running else { return }
        invalidate()
        refresh(); scheduleTimer()
    }
    func setCapsuleMetrics(_ metrics: Set<TelemetryMetric>) {
        guard metrics != capsuleMetrics else { return }
        capsuleMetrics = metrics
        guard running else { return }
        invalidate()
        refresh(); scheduleTimer()
    }
    func stop() {
        guard running else { return }
        running = false; sleeping = false
        invalidate(resetReader: true)
        timer?.invalidate(); timer = nil; samplingInterval = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        sleepObserver = nil
        if !inFlight { resetCollectorWhenIdle() }
        alerts.reset(); rules.reset(); previousPreferences = nil; previousDemand = nil
        capsuleMetrics = []; latestSnapshot = nil
    }
    private func scheduleTimer() {
        timer?.invalidate(); timer = nil; samplingInterval = nil
        guard running, !sleeping, demand.hasWork else { return }
        let interval = demand.highFrequency ? 2.0 : 30.0
        samplingInterval = interval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = demand.highFrequency ? 0.3 : 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    private func invalidate(resetReader: Bool = false) {
        generation &+= 1
        pendingRequest = nil
        if resetReader { resetEpoch &+= 1; codexReader.reset() }
    }
    private func resetCollectorWhenIdle() {
        let collector = collector
        collector.queue.async { collector.reset() }
    }
    func refresh() {
        guard running, !sleeping else { return }
        let preferences = settings.value, demand = demand
        if let previousDemand {
            // A disabled request may be coalesced away: retain each module's reset independently.
            if previousDemand.power && !demand.power { disabledEpochs.power &+= 1 }
            if previousDemand.compute && !demand.compute { disabledEpochs.compute &+= 1 }
            if previousDemand.network && !demand.network { disabledEpochs.network &+= 1 }
        }
        previousDemand = demand
        let request = Request(generation: generation, resetEpoch: resetEpoch, disabledEpochs: disabledEpochs,
            battery: battery(), preferences: preferences, demand: demand, codexQuota: codexReader.read(enabled: demand.codexQuota))
        if let injectedRead {
            // Existing deterministic evaluator tests may explicitly opt into synchronous reads.
            publish(injectedRead(request.battery, demand), request: request)
        } else if inFlight { pendingRequest = request }
        else { launch(request) }
    }
    private func launch(_ request: Request) {
        inFlight = true
        pendingRequest = nil
        let collector = collector, read = asynchronousRead
        collector.queue.async { [weak self] in
            let snapshot = collector.read(request, using: read)
            DispatchQueue.main.async { [weak self] in self?.complete(snapshot, request: request) }
        }
    }
    private func complete(_ snapshot: TelemetrySnapshot, request: Request) {
        inFlight = false
        if running, !sleeping, generation == request.generation,
           settings.value == request.preferences, demand == request.demand {
            publish(snapshot, request: request)
        }
        if !inFlight, running, let next = pendingRequest {
            pendingRequest = nil
            if next.generation == generation { launch(next) }
        } else if !running { resetCollectorWhenIdle() }
    }
    private func publish(_ value: TelemetrySnapshot, request: Request) {
        let preferences = request.preferences, demand = request.demand
        var snapshot = value
        // Filtering is also enforced at the routing boundary, including battery-derived metrics.
        if !demand.power { snapshot.power = nil }
        if !demand.compute { snapshot.compute = nil }
        if !demand.thermal { snapshot.thermal = nil }
        if !demand.network { snapshot.network = nil }
        if !demand.storage { snapshot.storage = nil }
        snapshot.codexQuota = demand.codexQuota ? request.codexQuota : nil
        latestSnapshot = snapshot
        onSnapshot?(snapshot)
        guard running, generation == request.generation else { return }
        let thermal = snapshot.thermal == .unknown ? nil : snapshot.thermal
        if thermal != observedThermal {
            observedThermal = thermal; builtinPresentedForTransition = false
        }
        if let thermal, alerts.shouldAlert(thermal, enabled: preferences.thermalAlert) {
            builtinPresentedForTransition = true
            onThermalAlert?(thermal)
        }
        let fired = rules.evaluate(rules: preferences.telemetryAlertRules, snapshot: snapshot, at: clock())
        for id in fired {
            guard let rule = preferences.telemetryAlertRules.first(where: { $0.id == id }) else { continue }
            if rule.condition == .stateChange, rule.source == .thermal, builtinPresentedForTransition { continue }
            onRuleAlert?(rule, snapshot)
        }
    }
    deinit {
        codexReader.reset()
        timer?.invalidate()
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
}
