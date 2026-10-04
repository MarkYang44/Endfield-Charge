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
    private var queue: [(BatterySnapshot, HUDKind)] = []
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
        if queued && isPresenting {
            if queue.count < 4 { queue.append((snapshot, kind)) }
            return
        }
        timer?.invalidate()
        if !queued { queue.removeAll() }
        preparePanel()
        guard let view, let panel else { return }
        isPresenting = true
        view.snapshot = snapshot
        view.kind = kind
        view.preferences = settings.value
        view.chinese = settings.chinese
        view.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        view.elapsed = 0
        position()
        panel.orderFrontRegardless()
        startTime = ProcessInfo.processInfo.systemUptime
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
            if !queue.isEmpty {
                let next = queue.removeFirst()
                show(next.0, kind: next.1, queued: true)
            } else {
                // Release the backing surface and view; no hidden HUD remains resident.
                panel?.contentView = nil
                panel?.close()
                panel = nil
                self.view = nil
            }
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
        timer?.invalidate()
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}

func screenID(_ screen: NSScreen) -> UInt32 {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
}
