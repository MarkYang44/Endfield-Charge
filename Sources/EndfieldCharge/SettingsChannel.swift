import Foundation
import Darwin
import ChargeCore

/// Reliable, private parent/child pipes; callbacks and model access stay on the main thread.
final class SettingsChannel {
    private let input: FileHandle
    private let output: FileHandle
    private var buffer = Data()
    private var discardingFrame = false
    private let writer = DispatchQueue(label: "com.markyang.endfieldcharge.settings-pipe")
    var onMessage: ((SettingsMessage) -> Void)?
    var onEnd: (() -> Void)?

    init(input: FileHandle, output: FileHandle) {
        self.input = input; self.output = output
        _ = fcntl(output.fileDescriptor, F_SETNOSIGPIPE, 1)
        input.readabilityHandler = { [weak self] handle in
            // Keep the channel alive during a read; deinit must not close the descriptor underneath it.
            guard let self else { return }
            let bytes = handle.availableData
            if bytes.isEmpty { handle.readabilityHandler = nil }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if bytes.isEmpty { self.onEnd?() } else { self.receive(bytes) }
            }
            withExtendedLifetime(self) {}
        }
    }

    func send(_ message: SettingsMessage) {
        guard var bytes = try? JSONEncoder().encode(message),
              bytes.count <= SettingsMessage.maximumPayloadBytes else { return }
        bytes.append(0x0A)
        writer.async { [weak self] in try? self?.output.write(contentsOf: bytes) }
    }

    func flush(completion: @escaping () -> Void) {
        writer.async { DispatchQueue.main.async(execute: completion) }
    }

    private func receive(_ bytes: Data) {
        var start = bytes.startIndex
        while start < bytes.endIndex {
            let newline = bytes[start...].firstIndex(of: 0x0A)
            let end = newline ?? bytes.endIndex
            if !discardingFrame {
                if end - start <= SettingsMessage.maximumPayloadBytes - buffer.count {
                    buffer.append(contentsOf: bytes[start..<end])
                } else {
                    buffer.removeAll(keepingCapacity: true)
                    discardingFrame = true
                }
            }
            guard let newline else { return }
            // Expanded Unicode configuration can span many reads. Budget each frame separately;
            // after an oversized frame, drain through its newline before accepting the next one.
            if !discardingFrame,
               let message = try? JSONDecoder().decode(SettingsMessage.self, from: buffer) { onMessage?(message) }
            buffer.removeAll(keepingCapacity: true)
            discardingFrame = false
            start = bytes.index(after: newline)
        }
    }

    deinit {
        input.readabilityHandler = nil
        try? input.close()
        try? output.close()
    }
}
