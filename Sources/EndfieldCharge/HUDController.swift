import AppKit
import ChargeCore

final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class HUDController {
    private var panel: HUDPanel?
    private var view: HUDView?
    private var timer: Timer?
    private var isPresenting = false
    private var startTime = 0.0
    private var observer: NSObjectProtocol?
    private struct Content {
        let battery: BatterySnapshot
        let kind: HUDKind
        let profile: CapsuleProfile?
        let rule: TelemetryAlertRule?
        let createdAt: Double
    }
    private var queue: [Content] = []
    private var current: Content?
    private var latestTelemetry: TelemetrySnapshot?
    var onCapsuleDemand: ((Set<TelemetryMetric>) -> Void)?
    var contextDisplayID: UInt32?
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.position() }
    }

    private func preparePanel() {
        guard panel == nil else { return }
        let view = HUDView(frame: NSRect(x: 0, y: 0, width: 620, height: 144))
        let panel = HUDPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = view
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        self.panel = panel
        self.view = view
    }

    func show(_ snapshot: BatterySnapshot, kind: HUDKind = .power, queued: Bool = false) {
        present(Content(battery: snapshot, kind: kind, profile: nil, rule: nil,
            createdAt: ProcessInfo.processInfo.systemUptime), queued: queued)
    }

    func showProfile(_ profile: CapsuleProfile, snapshot: TelemetrySnapshot?) {
        if profile.isDefaultBattery { show(snapshot?.battery ?? BatteryReader.read()); return }
        latestTelemetry = snapshot
        present(Content(battery: snapshot?.battery ?? BatterySnapshot(hasBattery: false), kind: .power,
            profile: profile, rule: nil, createdAt: ProcessInfo.processInfo.systemUptime), queued: false)
    }

    func showRule(_ rule: TelemetryAlertRule, snapshot: TelemetrySnapshot) {
        latestTelemetry = snapshot
        let profile = CapsuleProfile(id: "rule.\(rule.id)", title: rule.name, primaryMetric: rule.metric)
        present(Content(battery: snapshot.battery, kind: .power, profile: profile, rule: rule,
            createdAt: ProcessInfo.processInfo.systemUptime), queued: true)
    }

    func updateTelemetry(_ snapshot: TelemetrySnapshot) {
        latestTelemetry = snapshot
        guard let content = current, let profile = content.profile else { return }
        view?.capsule = CapsulePresentation(profile: profile, snapshot: displaySnapshot(snapshot), alert: content.rule != nil)
        view?.needsDisplay = true
    }

    private func displaySnapshot(_ snapshot: TelemetrySnapshot?) -> TelemetrySnapshot? {
        guard var snapshot else { return nil }
        let p = settings.value
        if !p.powerTelemetryEnabled { snapshot.power = nil }
        if !p.computeTelemetryEnabled { snapshot.compute = nil }
        if !p.networkTelemetryEnabled { snapshot.network = nil }
        if !p.storageTelemetryEnabled { snapshot.storage = nil }
        return snapshot
    }

    private func valid(_ content: Content) -> Bool {
        guard ProcessInfo.processInfo.systemUptime - content.createdAt <= 30 else { return false }
        if let rule = content.rule { return settings.value.telemetryAlertRules.contains(rule) && rule.enabled }
        if let profile = content.profile { return settings.value.capsuleProfiles.contains(profile) }
        return true
    }

    func preferencesChanged() {
        queue.removeAll()
        if current?.profile != nil { dismiss() }
    }

    func dismiss() {
        timer?.invalidate(); timer = nil
        queue.removeAll(); current = nil; isPresenting = false
        panel?.orderOut(nil); panel?.contentView = nil; panel?.close()
        panel = nil; view = nil
        onCapsuleDemand?([])
    }

    private func present(_ content: Content, queued: Bool) {
        if queued && isPresenting {
            if queue.count < 4 { queue.append(content) }
            return
        }
        timer?.invalidate()
        if !queued { queue.removeAll() }
        preparePanel()
        guard let view, let panel else { return }
        current = content
        isPresenting = true
        view.snapshot = content.battery
        view.kind = content.kind
        view.capsule = content.profile.map { CapsulePresentation(profile: $0, snapshot: displaySnapshot(latestTelemetry), alert: content.rule != nil) }
        view.preferences = settings.value
        view.chinese = settings.chinese
        view.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        view.elapsed = 0
        position()
        panel.orderFrontRegardless()
        startTime = ProcessInfo.processInfo.systemUptime
        if let profile = content.profile {
            onCapsuleDemand?(Set([profile.primaryMetric, profile.secondaryMetric, profile.ringMetric].compactMap { $0 }))
        } else { onCapsuleDemand?([]) }
        animate()
        tick()
    }

    private func animate() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tick() {
        guard let view else { return }
        view.elapsed = ProcessInfo.processInfo.systemUptime - startTime
        view.needsDisplay = true
        guard let delay = HUDFrame.redrawDelay(after: view.elapsed, duration: view.preferences.duration, reduceMotion: view.reduceMotion) else {
            timer?.invalidate(); timer = nil
            panel?.orderOut(nil)
            isPresenting = false
            current = nil
            queue.removeAll { !valid($0) }
            if !queue.isEmpty { present(queue.removeFirst(), queued: true) }
            else { dismiss() }
            return
        }
        if delay > 1.0 / 60 {
            timer?.invalidate()
            let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
                self?.animate()
                self?.tick()
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func position() {
        guard let panel, let view else { return }
        let display = settings.value.displayID == 0 ? contextDisplayID ?? 0 : settings.value.displayID
        let screen = NSScreen.screens.first { screenID($0) == display }
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let safe = screen.visibleFrame
        let scale = min(settings.value.scale, (safe.width - 24) / 620)
        let width = 620 * scale
        let height = 144 * scale
        let x: CGFloat
        switch settings.value.position {
        case "left": x = safe.minX + 12
        case "right": x = safe.maxX - width - 12
        default: x = safe.midX - width / 2
        }
        panel.setFrame(NSRect(x: x, y: safe.maxY - height + HUDView.topInset * scale - 2, width: width, height: height), display: true)
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
    }

    deinit {
        dismiss()
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}

func screenID(_ screen: NSScreen) -> UInt32 {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
}
