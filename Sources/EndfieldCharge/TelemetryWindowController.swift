import AppKit
import ChargeCore

final class TelemetryWindowController: NSWindowController, NSWindowDelegate {
    let view: TelemetryView
    var selectedTab: Int {
        get { view.selectedTab }
        set { view.selectedTab = newValue }
    }
    private let settings: AppSettings
    private let onClose: (Int, NSRect) -> Void
    private let onScreenChange: (() -> Void)?
    private var opened = false
    private var observers: [NSObjectProtocol] = []

    init(settings: AppSettings, selectedTab: Int, frame: NSRect?, onPreview: @escaping () -> Void,
         onClose: @escaping (Int, NSRect) -> Void, onScreenChange: (() -> Void)? = nil) {
        self.settings = settings
        self.onClose = onClose
        self.onScreenChange = onScreenChange
        view = TelemetryView(settings: settings, selectedTab: selectedTab, onPreview: onPreview)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        super.init(window: window)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = view
        refreshPreferences()
        if let frame { window.setFrame(frame, display: false) } else { window.center() }
        settings.onUIChange = { [weak self] in self?.refreshPreferences() }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didHideNotification,
            object: NSApp, queue: .main) { [weak self] _ in self?.view.stopHeaderAnimation() })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in self?.refreshPreferences() })
    }

    required init?(coder: NSCoder) { fatalError("Programmatic telemetry window") }

    func present() {
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if !opened { opened = true; view.startHeaderAnimation() }
    }

    func update(_ snapshot: TelemetrySnapshot) { view.update(snapshot) }

    private func refreshPreferences() {
        window?.title = "Endfield Charge · " + settings.text("遥测终端", "Telemetry Terminal")
        view.refreshPreferences()
    }

    func windowWillMiniaturize(_ notification: Notification) { view.stopHeaderAnimation() }
    func windowDidChangeScreen(_ notification: Notification) { onScreenChange?() }

    func windowWillClose(_ notification: Notification) {
        view.stopHeaderAnimation()
        settings.onUIChange = nil
        if let window { onClose(selectedTab, window.frame) }
    }

    deinit {
        view.stopHeaderAnimation()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
