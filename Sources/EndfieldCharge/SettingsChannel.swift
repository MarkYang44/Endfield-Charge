import Foundation
import Darwin
import ChargeCore

/// Reliable, private parent/child pipes; callbacks and model access stay on the main thread.
final class SettingsChannel {
    private let input: FileHandle
    private let output: FileHandle
    private var buffer = Data()
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
        guard var bytes = try? JSONEncoder().encode(message) else { return }
        bytes.append(0x0A)
        writer.async { [weak self] in try? self?.output.write(contentsOf: bytes) }
    }

    func flush(completion: @escaping () -> Void) {
        writer.async { DispatchQueue.main.async(execute: completion) }
    }

    private func receive(_ bytes: Data) {
        buffer.append(bytes)
        while let end = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<end])
            buffer.removeSubrange(...end)
            if let message = try? JSONDecoder().decode(SettingsMessage.self, from: line) { onMessage?(message) }
        }
        // Bound a malformed/incomplete frame; ordinary messages are below 1 KB.
        if buffer.count > 16_384 { buffer.removeAll(keepingCapacity: false) }
    }

    deinit {
        input.readabilityHandler = nil
        try? input.close()
        try? output.close()
    }
}
