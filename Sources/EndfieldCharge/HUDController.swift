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
    private var startTime = 0.0
    private var observer: NSObjectProtocol?
    private var motionObserver: NSObjectProtocol?
    private let reduceMotion: () -> Bool
    private struct Content {
        var battery: BatterySnapshot
        let kind: HUDKind
        let profile: CapsuleProfile?
        let rule: TelemetryAlertRule?
        let ruleSnapshot: TelemetrySnapshot?
    }
    private var current: Content?
    private var incoming: Content?
    private var completion: (() -> Void)?
    private var holding = false
    private var compactTransition = false
    private var latestTelemetry: TelemetrySnapshot?
    var onCapsuleDemand: ((Set<TelemetryMetric>) -> Void)?
    var contextDisplayID: UInt32?
    var hasAnimationTimer: Bool { timer != nil }
    private let settings: AppSettings

    init(settings: AppSettings, reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) {
        self.settings = settings; self.reduceMotion = reduceMotion
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.position() }
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in self?.motionChanged() }
    }
    private func preparePanel() {
        guard panel == nil else { return }
        let view = HUDView(frame: NSRect(x: 0, y: 0, width: 620, height: 144))
        let panel = HUDPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = view
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .statusBar; panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        self.panel = panel; self.view = view
    }
    private func content(_ battery: BatterySnapshot, kind: HUDKind = .power,
                         profile: CapsuleProfile? = nil, rule: TelemetryAlertRule? = nil,
                         ruleSnapshot: TelemetrySnapshot? = nil) -> Content {
        Content(battery: battery, kind: kind, profile: profile, rule: rule, ruleSnapshot: ruleSnapshot)
    }
    func render(battery: BatterySnapshot, kind: HUDKind, completion: @escaping () -> Void) {
        present(content(battery, kind: kind), completion: completion)
    }
    func render(profile: CapsuleProfile, snapshot: TelemetrySnapshot?, holding: Bool,
                compactTransition: Bool, completion: @escaping () -> Void) {
        latestTelemetry = snapshot
        present(content(snapshot?.battery ?? BatterySnapshot(hasBattery: false), profile: profile),
            holding: holding, compactTransition: compactTransition, completion: completion)
    }
    func render(rule: TelemetryAlertRule, snapshot: TelemetrySnapshot, completion: @escaping () -> Void) {
        latestTelemetry = snapshot
        present(content(snapshot.battery, rule: rule, ruleSnapshot: snapshot), completion: completion)
    }
    func updateTelemetry(_ snapshot: TelemetrySnapshot) {
        latestTelemetry = snapshot
        // Real battery changes update profiles, while an explicit demo/power event retains its payload.
        if current?.profile != nil { current?.battery = snapshot.battery }
        if incoming?.profile != nil { incoming?.battery = snapshot.battery }
        if let current { applyContent(current) }
    }
    func updateBattery(_ battery: BatterySnapshot) {
        latestTelemetry?.battery = battery
        if current?.profile != nil { current?.battery = battery }
        if incoming?.profile != nil { incoming?.battery = battery }
        if let current { applyContent(current) }
    }
    func clearTelemetry() { latestTelemetry = nil }
    private func displaySnapshot(_ snapshot: TelemetrySnapshot?) -> TelemetrySnapshot? {
        guard var snapshot else { return nil }
        let p = settings.value
        if !p.powerTelemetryEnabled { snapshot.power = nil }
        if !p.computeTelemetryEnabled { snapshot.compute = nil }
        if !p.thermalTelemetryEnabled { snapshot.thermal = nil }
        if !p.networkTelemetryEnabled { snapshot.network = nil }
        if !p.storageTelemetryEnabled { snapshot.storage = nil }
        return snapshot
    }
    func refreshPresentation() {
        guard let current else { return }
        view?.preferences = settings.value; view?.chinese = settings.chinese
        applyContent(current); position(); publishDemand()
    }
    func dismiss() {
        timer?.invalidate(); timer = nil
        current = nil; incoming = nil; completion = nil
        holding = false; compactTransition = false
        panel?.orderOut(nil); panel?.contentView = nil; panel?.close()
        panel = nil; view = nil
        // Complete teardown before callbacks: a fresh synchronous request can safely create a new owner.
        onCapsuleDemand?([])
    }
    private func applyContent(_ content: Content) {
        guard let view else { return }
        view.snapshot = content.battery; view.kind = content.kind
        var snapshot = displaySnapshot(latestTelemetry)
        snapshot?.battery = content.battery
        view.accentOverride = nil
        if let rule = content.rule, let eventSnapshot = displaySnapshot(content.ruleSnapshot) {
            // State labels describe the observed event, not a later state during its display.
            view.capsule = CapsulePresentation(rule: rule,
                snapshot: rule.condition == .stateChange ? eventSnapshot : snapshot ?? eventSnapshot, chinese: settings.chinese)
        } else if let profile = content.profile {
            if profile.isBatteryLayout {
                view.capsule = nil
                if !profile.colorConditions.isEmpty { view.accentOverride = snapshot.map { profile.resolvedAccent(in: $0) } ?? .theme }
            } else { view.capsule = CapsulePresentation(profile: profile, snapshot: snapshot) }
        } else { view.capsule = nil }
        view.needsDisplay = true
    }
    private func publishDemand() {
        guard let content = incoming ?? current else { onCapsuleDemand?([]); return }
        if let profile = content.profile {
            onCapsuleDemand?(Set([profile.primaryMetric, profile.secondaryMetric, profile.ringMetric].compactMap { $0 })
                .union(profile.colorConditions.map(\.metric)))
        } else if let rule = content.rule {
            // State collectors already run when enabled; a visible state event still requests the fast shared cadence.
            onCapsuleDemand?(rule.condition == .threshold ? [rule.metric] : [.batteryPercent])
        } else { onCapsuleDemand?([]) }
    }
    private func present(_ content: Content, holding: Bool = false,
                         compactTransition: Bool = false, completion: @escaping () -> Void) {
        timer?.invalidate(); timer = nil
        let outgoing = current
        preparePanel()
        guard let view, let panel else { return }
        self.holding = holding; self.compactTransition = compactTransition
        self.completion = completion
        incoming = nil; current = content
        view.preferences = settings.value; view.chinese = settings.chinese
        view.reduceMotion = reduceMotion(); view.compactHold = false; view.frameOverride = nil; view.elapsed = 0
        if holding && compactTransition && !view.reduceMotion, let outgoing {
            current = outgoing; incoming = content
        }
        if let current { applyContent(current) }
        position(); panel.orderFrontRegardless()
        startTime = ProcessInfo.processInfo.systemUptime
        animate(); tick()
        publishDemand() // Everything the callback might reenter is installed first.
    }
    private func animate() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func motionChanged() {
        guard let view else { return }
        view.reduceMotion = reduceMotion()
        if view.reduceMotion {
            if let incoming { current = incoming; self.incoming = nil; applyContent(incoming) }
            tick()
        }
    }
    private func tick() {
        guard let view else { return }
        view.elapsed = ProcessInfo.processInfo.systemUptime - startTime
        if holding {
            let compact = HUDFrame.at(seconds: 2.52, duration: 10)
            if view.reduceMotion {
                view.frameOverride = compact; view.compactHold = true
            } else if compactTransition {
                let elapsed = view.elapsed
                if elapsed >= 0.18, let incoming { current = incoming; self.incoming = nil; applyContent(incoming) }
                var frame = compact
                let progress = min(1, max(0, elapsed < 0.18 ? 1 - elapsed / 0.18 : (elapsed - 0.18) / 0.18))
                frame.overallScale = progress * progress * (3 - 2 * progress)
                view.frameOverride = frame; view.compactHold = elapsed >= 0.36
            } else {
                view.frameOverride = HUDFrame.at(seconds: min(2.52, view.elapsed), duration: 10)
                view.compactHold = view.elapsed >= 2.52
            }
            view.needsDisplay = true
            if view.compactHold { timer?.invalidate(); timer = nil }
            return
        }
        // Reduced motion switches directly to compact content and keeps the complete configured dwell.
        if view.reduceMotion {
            var frame = HUDFrame.at(seconds: 2.52, duration: 10)
            if view.kind != .power && view.capsule == nil {
                frame = HUDFrame.at(seconds: 0.15, duration: 10, reduceMotion: true)
                frame.numbersOpacity = 0
            }
            view.frameOverride = frame
            view.compactHold = true
        }
        view.needsDisplay = true
        guard view.elapsed < view.preferences.duration else { finished(); return }
        let delay = view.reduceMotion ? view.preferences.duration - view.elapsed
            : HUDFrame.redrawDelay(after: view.elapsed, duration: view.preferences.duration) ?? 0
        if delay > 1.0 / 60 {
            timer?.invalidate()
            let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in self?.animate(); self?.tick() }
            self.timer = timer; RunLoop.main.add(timer, forMode: .common)
        }
    }
    private func finished() {
        let callback = completion
        // Release the old native owner before demand/completion callbacks can reenter render().
        dismiss()
        callback?()
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
        if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }
    }
}

func screenID(_ screen: NSScreen) -> UInt32 {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
}
