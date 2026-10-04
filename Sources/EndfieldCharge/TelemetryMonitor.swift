import AppKit
import ChargeCore

final class TelemetryMonitor {
    private let settings: AppSettings
    private let battery: () -> BatterySnapshot
    private let reader = TelemetryReader()
    private var alerts = ThermalAlertState()
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var running = false
    private var panelVisible = false
    private var previousPreferences: Preferences?
    var onSnapshot: ((TelemetrySnapshot) -> Void)?
    var onThermalAlert: ((ThermalLevel) -> Void)?

    init(settings: AppSettings, battery: @escaping () -> BatterySnapshot) {
        self.settings = settings; self.battery = battery
    }

    func start() {
        guard !running else { return }
        running = true
        reader.reset(); alerts.reset()
        previousPreferences = settings.value
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.running else { return }
            self.reader.reset(); self.refresh()
        }
        refresh(); scheduleTimer()
    }

    func preferencesChanged() {
        guard running else { return }
        let current = settings.value
        if previousPreferences?.thermalTelemetryEnabled != current.thermalTelemetryEnabled { alerts.reset() }
        previousPreferences = current
        // Reader clears disabled state immediately; enabling follows an unknown CPU baseline.
        refresh(); scheduleTimer()
    }

    func setPanelVisible(_ visible: Bool) {
        guard visible != panelVisible else { return }
        panelVisible = visible
        guard running else { return }
        refresh(); scheduleTimer()
    }

    func stop() {
        running = false
        timer?.invalidate(); timer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        reader.reset(); alerts.reset(); previousPreferences = nil
    }

    private func scheduleTimer() {
        timer?.invalidate(); timer = nil
        let preferences = settings.value
        guard running, preferences.powerTelemetryEnabled || preferences.computeTelemetryEnabled
                || preferences.thermalTelemetryEnabled else { return }
        let interval = panelVisible ? 2.0 : 30.0
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = panelVisible ? 0.3 : 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func refresh() {
        guard running else { return }
        let preferences = settings.value
        let snapshot = reader.read(battery: battery(), powerEnabled: preferences.powerTelemetryEnabled,
            computeEnabled: preferences.computeTelemetryEnabled, thermalEnabled: preferences.thermalTelemetryEnabled)
        onSnapshot?(snapshot)
        if let thermal = snapshot.thermal, alerts.shouldAlert(thermal, enabled: preferences.thermalAlert) {
            onThermalAlert?(thermal)
        }
    }

    deinit {
        timer?.invalidate()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
}
