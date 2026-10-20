import AppKit
import ChargeCore

/// AppKit control/font/toolbar caches disappear when this on-demand role exits.
final class SettingsApplicationDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings(persistsChanges: false)
    private let parentPID: Int32
    private let tab: Int
    private let frame: NSRect?
    private var controller: SettingsWindowController?
    private var channel: SettingsChannel?
    private var session: SettingsConfigurationSession?
    private var closing = false
    private var closeTimer: Timer?

    init(parentPID: Int32, tab: Int, frame: String) {
        self.parentPID = parentPID
        self.tab = (0..<7).contains(tab) ? tab : 0
        let rect = NSRectFromString(frame)
        self.frame = rect.width.isFinite && rect.height.isFinite && rect.width > 0 && rect.height > 0
            && rect.origin.x.isFinite && rect.origin.y.isFinite ? rect : nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard NSRunningApplication(processIdentifier: parentPID)?.isTerminated == false else { NSApp.terminate(nil); return }
        channel = SettingsChannel(input: .standardInput, output: .standardOutput)
        channel?.onEnd = { [weak self] in self?.session?.disconnect(); NSApp.terminate(nil) }
        channel?.onMessage = { [weak self] message in self?.receive(message) }
        session = SettingsConfigurationSession(settings: settings) { [weak self] in self?.channel?.send($0) }
        controller = SettingsWindowController(settings: settings, selectedTab: tab, frame: frame, onPreview: { [weak self] charging in
            self?.send(charging.map { $0 ? .demoCharge : .demoBattery } ?? .preview)
        }, onClose: { [weak self] tab, frame in
            guard let self else { return }
            self.closing = true
            if let message = self.session?.closed(tab: tab, frame: NSStringFromRect(frame)) { self.channel?.send(message) }
            self.controller = nil
            // Parent acknowledgment guarantees final settings/tab/frame were received before exit.
            self.closeTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { _ in NSApp.terminate(nil) }
        }, onScreenChange: { [weak self] in self?.send(.screen) })
        controller?.onCapsulePreview = { [weak self] id in
            guard let self else { return }
            self.channel?.send(SettingsMessage(.previewCapsule, revision: self.session?.revision,
                displayID: self.controller?.window?.screen.map(screenID), profileID: id))
        }
        controller?.onConfigurationRequest = { [weak self] action in
            guard let self, let session = self.session else { throw SettingsConfigurationSession.SessionError.unavailable }
            try session.submit(action)
        }
        session?.onBusyChange = { [weak self] in self?.controller?.setConfigurationPending($0) }
        session?.onResult = { [weak self] in self?.controller?.configurationCompleted($0) }
        controller?.setConfigurationPending(true)
        controller?.present()
        session?.start()
    }

    private func send(_ command: SettingsMessage.Command, preferences: Preferences? = nil) {
        let display = controller?.window?.screen.map(screenID)
        channel?.send(SettingsMessage(command, preferences: preferences, revision: session?.revision, displayID: display))
    }

    private func receive(_ message: SettingsMessage) {
        if message.command == .closeAck {
            closeTimer?.invalidate()
            channel?.flush { NSApp.terminate(nil) }
            return
        }
        if message.command == .show {
            if closing { send(.reopen) } else { controller?.present() }
        }
        session?.receive(message)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        send(.preview)
        return false
    }
}
