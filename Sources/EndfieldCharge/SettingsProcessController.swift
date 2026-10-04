import AppKit
import ChargeCore

/// Retains only a process, private pipe and tiny reopen state. Settings views live in the child.
final class SettingsProcessController {
    private let settings: AppSettings
    private let onPreview: (Bool?) -> Void
    private let onScreen: (UInt32?) -> Void
    private var process: Process?
    private var channel: SettingsChannel?
    private var revision = 0
    private var closing = false
    private var pendingReopen = false
    private var stopping = false
    private var pipeEnded = false
    private var processExited = false
    private var tab = 0
    private var frame = "center"

    init(settings: AppSettings, onPreview: @escaping (Bool?) -> Void, onScreen: @escaping (UInt32?) -> Void) {
        self.settings = settings; self.onPreview = onPreview; self.onScreen = onScreen
    }

    func open() {
        guard !stopping else { return }
        if let process {
            if closing || !process.isRunning { pendingReopen = true } else { sendState(.show) }
            return
        }
        guard let executable = Bundle.main.executableURL else { return }
        let child = Process(), toChild = Pipe(), fromChild = Pipe()
        child.executableURL = executable
        child.arguments = ["--settings-ui", String(ProcessInfo.processInfo.processIdentifier), String(tab), frame]
        child.standardInput = toChild
        child.standardOutput = fromChild
        child.terminationHandler = { [weak self] completed in
            let pid = completed.processIdentifier
            DispatchQueue.main.async { [weak self] in self?.didExit(pid) }
        }
        do {
            try child.run()
            process = child
            revision = 0
            pipeEnded = false
            processExited = false
            channel = SettingsChannel(input: fromChild.fileHandleForReading, output: toChild.fileHandleForWriting)
            let pid = child.processIdentifier
            channel?.onMessage = { [weak self] message in
                guard self?.process?.processIdentifier == pid else { return }
                self?.receive(message)
            }
            channel?.onEnd = { [weak self] in
                guard let self, self.process?.processIdentifier == pid else { return }
                self.pipeEnded = true
                if self.processExited || self.process?.isRunning == false { self.finish(pid) }
            }
        } catch { NSAlert(error: error).runModal() }
    }

    private func receive(_ message: SettingsMessage) {
        if let display = message.displayID { onScreen(display) }
        switch message.command {
        case .ready, .changed:
            apply(message)
            sendState()
        case .preview: onPreview(nil)
        case .demoCharge: onPreview(true)
        case .demoBattery: onPreview(false)
        case .screen: break
        case .closed:
            closing = true
            apply(message)
            if let selected = message.tab, (0..<4).contains(selected) { tab = selected }
            if let saved = message.frame, validFrame(saved) { frame = saved }
            onScreen(nil)
            channel?.send(SettingsMessage(.closeAck))
        case .reopen: pendingReopen = true
        default: break
        }
    }

    private func apply(_ message: SettingsMessage) {
        guard let incoming = message.revision, incoming >= revision, let value = message.preferences else { return }
        revision = incoming
        settings.applyFromPeer(value)
    }

    private func sendState(_ command: SettingsMessage.Command = .state) {
        // Feedback never overwrites the UI's newer preference model.
        channel?.send(SettingsMessage(command, revision: revision, shortcutMessage: settings.shortcutMessage))
    }

    private func validFrame(_ value: String) -> Bool {
        let rect = NSRectFromString(value)
        return rect.width.isFinite && rect.height.isFinite && rect.width > 0 && rect.height > 0
            && rect.origin.x.isFinite && rect.origin.y.isFinite
    }

    private func didExit(_ pid: Int32) {
        guard process?.processIdentifier == pid else { return }
        processExited = true
        if pipeEnded { finish(pid) }
    }

    private func finish(_ pid: Int32) {
        guard process?.processIdentifier == pid else { return }
        process = nil; channel = nil; closing = false
        onScreen(nil)
        if pendingReopen { pendingReopen = false; open() }
    }

    func stop() {
        stopping = true
        pendingReopen = false
        if process?.isRunning == true { process?.terminate() }
    }
    deinit { stop() }
}
