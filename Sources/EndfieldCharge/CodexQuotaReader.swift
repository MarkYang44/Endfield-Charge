import Foundation
import Darwin
import ChargeCore

/// Main-thread cache. CLI work has its own queue and never occupies the telemetry collector.
final class CodexQuotaReader {
    typealias Fetch = (@escaping (CodexQuotaSnapshot?) -> Void) -> (() -> Void)
    private let clock: () -> Double
    private let fetch: Fetch
    private var cache: CodexQuotaSnapshot?
    private var receivedAt: Double?
    private var attemptedAt: Double?
    private var cancel: (() -> Void)?
    private var inFlight = false
    private var enabled = false
    private var generation: UInt64 = 0

    init(clock: @escaping () -> Double = { Date().timeIntervalSince1970 }, fetch: Fetch? = nil) {
        self.clock = clock
        let queue = DispatchQueue(label: "com.markyang.endfieldcharge.codex-quota", qos: .utility)
        self.fetch = fetch ?? { completion in
            let request = CodexQuotaRequest()
            queue.async { completion(request.read()) }
            return { request.cancel() }
        }
    }
    func read(enabled: Bool) -> CodexQuotaSnapshot? {
        self.enabled = enabled
        guard enabled else { cancelPending(); return nil }
        let now = clock()
        let fresh = receivedAt.map { now >= $0 && now - $0 < 300 } == true
        let resetDue = cache.map { [$0.fiveHour, $0.weekly].compactMap { $0?.resetsAt }.contains { $0 <= now } } ?? false
        // A service response may retain an elapsed reset; show it as "Reset due" rather than
        // hiding a recent successful response (or its other valid window).
        if (!fresh || resetDue), !inFlight, attemptedAt.map({ now >= $0 && now - $0 < 60 }) != true {
            attemptedAt = now; inFlight = true
            let epoch = generation
            cancel = fetch { [weak self] result in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.inFlight = false; self.cancel = nil
                    guard self.enabled, self.generation == epoch else { return }
                    self.cache = result; self.receivedAt = result == nil ? nil : self.clock()
                }
            }
        }
        return fresh ? cache : nil
    }
    private func cancelPending() {
        guard cancel != nil else { return }
        generation &+= 1
        cancel?(); cancel = nil
        // Keep inFlight until the worker has closed/reaped its process; no overlapping child.
    }
    func reset() {
        cancelPending(); generation &+= 1
        cache = nil; receivedAt = nil; attemptedAt = nil
    }
    deinit { cancel?() }
}

/// One read-only newline JSON-RPC session. All output is bounded; stderr is discarded.
final class CodexQuotaRequest {
    private let lock = NSLock()
    private var canceled = false
    private var pid: Int32?
    private let executable: URL?
    private let timeout: Double
    private let maximumOutput: Int

    init(executable: URL? = nil, timeout: Double = 8, maximumOutput: Int = 262_144) {
        self.executable = executable; self.timeout = timeout; self.maximumOutput = maximumOutput
    }
    static func discoverCLI() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/codex" } + [
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(home)/.local/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "\(home)/Applications/Codex.app/Contents/Resources/codex",
            "\(home)/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }
    func cancel() {
        lock.lock(); canceled = true
        if let pid { kill(pid, SIGTERM) }
        lock.unlock()
    }
    private var isCanceled: Bool {
        lock.lock(); defer { lock.unlock() }; return canceled
    }
    func read() -> CodexQuotaSnapshot? {
        guard !isCanceled, let executable = executable ?? Self.discoverCLI() else { return nil }
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = executable
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.arguments = ["app-server", "--listen", "stdio://"]
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        var launched = false
        let started = ProcessInfo.processInfo.systemUptime
        defer {
            // Reap this request's child even after timeout, oversized output, malformed data or cancellation.
            try? input.fileHandleForWriting.close()
            lock.lock()
            if process.isRunning { process.terminate() }
            pid = nil
            lock.unlock()
            let deadline = ProcessInfo.processInfo.systemUptime + 0.2
            while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.01) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            if launched { process.waitUntilExit() }
            try? output.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
            try? input.fileHandleForReading.close()
        }
        do { try process.run(); launched = true } catch { return nil }
        lock.lock(); pid = process.processIdentifier
        if canceled { kill(process.processIdentifier, SIGTERM) }
        lock.unlock()
        try? output.fileHandleForWriting.close()
        try? input.fileHandleForReading.close()
        func send(_ message: [String: Any]) -> Bool {
            guard let data = try? JSONSerialization.data(withJSONObject: message) else { return false }
            do { try input.fileHandleForWriting.write(contentsOf: data + Data([10])); return true }
            catch { return false }
        }
        guard send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "endfield_charge", "version": "1.3.0"]]]) else { return nil }
        var buffer = Data(), total = 0, initialized = false
        let fd = output.fileHandleForReading.fileDescriptor
        var bytes = [UInt8](repeating: 0, count: 8192)
        while !isCanceled && ProcessInfo.processInfo.systemUptime - started < timeout {
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 100)
            if ready < 0 { if errno == EINTR { continue }; return nil }
            if ready == 0 { if !process.isRunning { return nil }; continue }
            let count = Darwin.read(fd, &bytes, bytes.count)
            guard count > 0 else { return nil }
            total += count
            guard total <= maximumOutput else { return nil }
            buffer.append(contentsOf: bytes.prefix(count))
            while let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
                guard let response = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return nil }
                guard let id = response["id"] as? Int else { continue } // Bounded notifications may arrive between replies.
                if id == 1 && !initialized {
                    guard response["error"] == nil, response["result"] != nil else { return nil }
                    initialized = true
                    guard send(["method": "initialized", "params": [:]]), send(["id": 2, "method": "account/rateLimits/read"]) else { return nil }
                } else if id == 2 && initialized {
                    guard response["error"] == nil, let result = response["result"] as? [String: Any],
                          let data = try? JSONSerialization.data(withJSONObject: result) else { return nil }
                    return try? CodexQuotaSnapshot.parse(data)
                }
            }
        }
        return nil
    }
    deinit { cancel() }
}
