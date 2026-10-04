import AppKit
import ChargeCore

/// This child owns only the terminal window; the resident supplies all samples and preferences.
final class TelemetryApplicationDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let parentPID: Int32
    private let tab: Int
    private let frame: NSRect?
    private var controller: TelemetryWindowController?
    private var channel: SettingsChannel?
    private var revision = 0
    private var closing = false
    private var closeTimer: Timer?
    private var visibilityObservers: [NSObjectProtocol] = []

    init(parentPID: Int32, tab: Int, frame: String) {
        self.parentPID = parentPID
        self.tab = (0..<3).contains(tab) ? tab : 0
        let rect = NSRectFromString(frame)
        self.frame = rect.width.isFinite && rect.height.isFinite && rect.width > 0 && rect.height > 0
            && rect.origin.x.isFinite && rect.origin.y.isFinite ? rect : nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard NSRunningApplication(processIdentifier: parentPID)?.isTerminated == false else {
            NSApp.terminate(nil); return
        }
        channel = SettingsChannel(input: .standardInput, output: .standardOutput)
        channel?.onEnd = { [weak self] in self?.controller?.view.stopHeaderAnimation(); NSApp.terminate(nil) }
        channel?.onMessage = { [weak self] message in self?.receive(message) }
        controller = TelemetryWindowController(settings: settings, selectedTab: tab, frame: frame,
            onPreview: { [weak self] in self?.send(.preview) },
            onClose: { [weak self] tab, frame in
                guard let self else { return }
                self.closing = true
                self.channel?.send(SettingsMessage(.closed, revision: self.revision, tab: tab,
                    frame: NSStringFromRect(frame)))
                // The writer queue drains the final frame before waiting for the parent's acknowledgment.
                self.channel?.flush {}
                self.controller = nil
                self.removeVisibilityObservers()
                self.closeTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { _ in NSApp.terminate(nil) }
            }, onScreenChange: { [weak self] in self?.send(.screen) })
        observeVisibility()
        controller?.present()
        // Never send this child's disk-cached preferences back to the resident.
        send(.ready)
        sendVisibility()
    }

    private func send(_ command: SettingsMessage.Command) {
        channel?.send(SettingsMessage(command, revision: revision,
            displayID: controller?.window?.screen.map(screenID)))
    }

    private func observeVisibility() {
        let center = NotificationCenter.default
        if let window = controller?.window {
            for name in [NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
                visibilityObservers.append(center.addObserver(forName: name, object: window, queue: .main) {
                    [weak self] _ in self?.sendVisibility()
                })
            }
        }
        for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
            visibilityObservers.append(center.addObserver(forName: name, object: NSApp, queue: .main) {
                [weak self] _ in self?.sendVisibility()
            })
        }
    }

    private func sendVisibility() {
        guard !closing else { return }
        let window = controller?.window
        let visible = window?.isVisible == true && window?.isMiniaturized == false && !NSApp.isHidden
        channel?.send(SettingsMessage(.visibility, visible: visible))
    }

    private func removeVisibilityObservers() {
        for observer in visibilityObservers { NotificationCenter.default.removeObserver(observer) }
        visibilityObservers.removeAll()
    }

    private func receive(_ message: SettingsMessage) {
        if message.command == .closeAck {
            closeTimer?.invalidate()
            channel?.flush { NSApp.terminate(nil) }
            return
        }
        if message.command == .show {
            if closing { send(.reopen) } else { controller?.present(); sendVisibility() }
        }
        guard !closing, message.command == .telemetry || message.command == .show || message.command == .state else { return }
        // This stream is parent-owned and read-only: it does not share the settings editor's revision handshake.
        if let preferences = message.preferences { settings.applyFromPeer(preferences) }
        if let snapshot = message.telemetry { controller?.update(snapshot) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if closing { send(.reopen) } else { controller?.present(); sendVisibility() }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        closeTimer?.invalidate()
        removeVisibilityObservers()
        controller?.view.stopHeaderAnimation()
        settings.onUIChange = nil
    }

    deinit { removeVisibilityObservers() }
}
