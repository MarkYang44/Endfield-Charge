import AppKit
import ChargeCore

final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class HUDController {
    private let panel: HUDPanel
    private let view = HUDView(frame: NSRect(x: 0, y: 0, width: 620, height: 144))
    private var timer: Timer?
    private var startTime = 0.0
    private var observer: NSObjectProtocol?
    private var queue: [(BatterySnapshot, HUDKind)] = []
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        panel = HUDPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
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
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.position() }
    }

    func show(_ snapshot: BatterySnapshot, kind: HUDKind = .power, queued: Bool = false) {
        if queued && timer != nil {
            if queue.count < 4 { queue.append((snapshot, kind)) }
            return
        }
        timer?.invalidate()
        if !queued { queue.removeAll() }
        view.snapshot = snapshot
        view.kind = kind
        view.preferences = settings.value
        view.chinese = settings.chinese
        view.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        view.elapsed = 0
        position()
        panel.orderFrontRegardless()
        startTime = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        tick()
    }

    private func tick() {
        view.elapsed = ProcessInfo.processInfo.systemUptime - startTime
        view.needsDisplay = true
        if view.elapsed >= view.preferences.duration {
            timer?.invalidate(); timer = nil
            panel.orderOut(nil)
            if !queue.isEmpty {
                let next = queue.removeFirst()
                show(next.0, kind: next.1, queued: true)
            }
        }
    }

    func position() {
        let screen = NSScreen.screens.first { screenID($0) == settings.value.displayID }
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
        // visibleFrame avoids the menu bar and the camera housing on MacBooks.
        panel.setFrame(NSRect(x: x, y: safe.maxY - height - 8, width: width, height: height), display: true)
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
