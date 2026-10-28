import AppKit
import ChargeCore

/// The resident's only route to the HUD. Renderer completion and sampler callbacks can be
/// synchronous; serialize them so demand changes never overwrite a newly presented surface.
final class CapsulePlaybackController {
    private enum Content {
        case battery(BatterySnapshot, HUDKind)
        case profile(CapsuleProfile)
        case rule(TelemetryAlertRule, TelemetrySnapshot)
    }
    private let settings: AppSettings
    private let hud: HUDController
    private let clock: () -> Double
    private var scheduler: CapsulePlaybackScheduler
    private var payloads: [String: Content] = [:]
    private var latestSnapshot: TelemetrySnapshot?
    private var timer: Timer?
    private var pending: [() -> Void] = []
    private var processing = false
    private var stopped = false
    var onCapsuleDemand: ((Set<TelemetryMetric>) -> Void)?
    var onHiddenChanged: ((Bool) -> Void)?
    var isHidden: Bool { scheduler.isHidden }
    var nextDeadline: Double? { scheduler.nextDeadline }

    init(settings: AppSettings, hud: HUDController,
         clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.settings = settings; self.hud = hud; self.clock = clock
        scheduler = CapsulePlaybackScheduler(clock: clock)
        hud.onCapsuleDemand = { [weak self] in self?.onCapsuleDemand?($0) }
    }
    func preferencesChanged() {
        enqueue { [self] in
            let invalid = Set(payloads.compactMap { valid($0.value) ? nil : $0.key })
            // Invalidate payloads in the same transition as configuration, before any queued show action.
            apply(scheduler.configure(settings.value, canceling: invalid))
            hud.refreshPresentation()
        }
    }
    func updateTelemetry(_ snapshot: TelemetrySnapshot) {
        enqueue { [self] in
            latestSnapshot = snapshot
            hud.updateTelemetry(snapshot)
            apply(scheduler.receivedFreshSnapshot())
        }
    }
    func updateBattery(_ battery: BatterySnapshot) {
        enqueue { [self] in
            latestSnapshot?.battery = battery
            hud.updateBattery(battery)
        }
    }
    func showPower(_ battery: BatterySnapshot) { submit(.battery(battery, .power), priority: .power) }
    func showAlert(_ battery: BatterySnapshot, kind: HUDKind) { submit(.battery(battery, kind), priority: .alert) }
    func showRule(_ rule: TelemetryAlertRule, snapshot: TelemetrySnapshot) {
        submit(.rule(rule, snapshot), priority: .alert, ruleID: rule.id)
    }
    func previewBattery(_ battery: BatterySnapshot) { submit(.battery(battery, .power), priority: .preview) }
    func previewProfile(id: String) {
        guard let profile = settings.value.capsuleProfiles.first(where: { $0.id == id }) else { return }
        submit(.profile(profile), priority: .preview, profileID: id)
    }
    func previewSelected() {
        if settings.value.playback.persistent || scheduler.isHidden { previewProfile(id: settings.value.selectedCapsuleID) }
        else { enqueue { [self] in apply(scheduler.startCycle()) } }
    }
    func setHidden(_ hidden: Bool) {
        enqueue { [self] in apply(scheduler.setHidden(hidden)); onHiddenChanged?(scheduler.isHidden) }
    }
    func suspend() {
        enqueue { [self] in latestSnapshot = nil; apply(scheduler.suspend()); hud.clearTelemetry() }
    }
    func wake() {
        enqueue { [self] in latestSnapshot = nil; apply(scheduler.wake()); hud.clearTelemetry() }
    }
    func advance() { enqueue { [self] in apply(scheduler.advance()) } }
    func stop() {
        stopped = true; pending.removeAll(); timer?.invalidate(); timer = nil
        _ = scheduler.suspend(); payloads.removeAll(); latestSnapshot = nil
        hud.dismiss()
    }
    private func valid(_ content: Content) -> Bool {
        let preferences = settings.value
        switch content {
        case .profile(let profile): return preferences.capsuleProfiles.contains(profile)
        case .rule(let rule, _):
            guard rule.enabled, preferences.telemetryAlertRules.contains(rule) else { return false }
            if rule.condition == .stateChange {
                switch rule.source {
                case .thermal: return preferences.thermalTelemetryEnabled
                case .memoryPressure: return preferences.computeTelemetryEnabled
                case nil: return false
                }
            }
            switch rule.metric {
            case .batteryEnergyWh, .batteryPercent, .codexFiveHourRemainingPercent, .codexWeeklyRemainingPercent: return true
            case .cpuPercent, .memoryUsedBytes, .memoryPercent: return preferences.computeTelemetryEnabled
            case .networkDownloadBytesPerSecond, .networkUploadBytesPerSecond: return preferences.networkTelemetryEnabled
            case .storageAvailableBytes, .storageUsedPercent: return preferences.storageTelemetryEnabled
            }
        case .battery(_, let kind):
            switch kind {
            case .power: return true // Real power and explicit demos are independent of optional alert switches.
            case .lowBattery: return preferences.lowBatteryAlert
            case .fullyCharged: return preferences.fullBatteryAlert
            case .lowPowerEnabled, .lowPowerDisabled: return preferences.lowPowerAlert
            case .thermalWarning, .thermalCritical: return preferences.thermalAlert && preferences.thermalTelemetryEnabled
            }
        }
    }
    private func submit(_ content: Content, priority: CapsulePlaybackScheduler.Priority,
                        profileID: String? = nil, ruleID: String? = nil) {
        enqueue { [self] in
            guard valid(content) else { return }
            let id = UUID().uuidString
            payloads[id] = content
            apply(scheduler.submit(.init(id: id, priority: priority, profileID: profileID, ruleID: ruleID)))
        }
    }
    private func enqueue(_ operation: @escaping () -> Void) {
        guard !stopped else { return }
        pending.append(operation)
        guard !processing else { return }
        processing = true
        while !pending.isEmpty { pending.removeFirst()() }
        processing = false
        let retained = scheduler.retainedRequestIDs
        payloads = payloads.filter { retained.contains($0.key) }
        scheduleTimer()
    }
    private func apply(_ actions: [CapsulePlaybackScheduler.Action]) {
        for action in actions {
            switch action {
            case .hide: hud.dismiss()
            case .show(let presentation):
                let content: Content?
                if presentation.request.priority == .ambient || presentation.request.beginsCycle {
                    content = settings.value.capsuleProfiles.first { $0.id == presentation.request.profileID }.map(Content.profile)
                } else { content = payloads[presentation.request.id] }
                guard let content else { continue }
                let completion: () -> Void = { [weak self] in
                    self?.enqueue { [weak self] in
                        guard let self else { return }
                        self.apply(self.scheduler.completed(serial: presentation.serial))
                    }
                }
                switch content {
                case .battery(let battery, let kind):
                    hud.render(battery: battery, kind: kind, completion: completion)
                case .profile(let profile):
                    hud.render(profile: profile, snapshot: latestSnapshot, holding: presentation.holding,
                        compactTransition: presentation.compactTransition, completion: completion)
                case .rule(let rule, let snapshot):
                    hud.render(rule: rule, snapshot: snapshot, completion: completion)
                }
            }
        }
    }
    private func scheduleTimer() {
        timer?.invalidate(); timer = nil
        guard let deadline = scheduler.nextDeadline, !stopped else { return }
        let timer = Timer(timeInterval: max(0.001, deadline - clock()), repeats: false) { [weak self] _ in self?.advance() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    deinit {
        timer?.invalidate(); hud.dismiss()
        // The renderer forwards weakly; during owner teardown it cannot publish this release.
        onCapsuleDemand?([])
    }
}
