import Foundation

public struct NetworkTelemetry: Codable, Equatable {
    /// Rates are unknown until two valid observations of at least one matching interface.
    public var downloadBytesPerSecond: Double?
    public var uploadBytesPerSecond: Double?
    /// Traffic observed during valid sampling intervals in this session, not OS lifetime counters.
    public var receivedBytes: UInt64
    public var sentBytes: UInt64
    public var interfaces: [String]
    public var interfaceCount: Int { interfaces.count }

    public init(downloadBytesPerSecond: Double?, uploadBytesPerSecond: Double?, receivedBytes: UInt64,
                sentBytes: UInt64, interfaces: [String]) {
        self.downloadBytesPerSecond = downloadBytesPerSecond.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.uploadBytesPerSecond = uploadBytesPerSecond.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.receivedBytes = receivedBytes; self.sentBytes = sentBytes
        self.interfaces = Array(Set(interfaces)).sorted()
    }
}

public struct NetworkInterfaceCounter: Equatable {
    public var name: String
    public var index: UInt32
    public var receivedBytes: UInt64
    public var sentBytes: UInt64
    public init(name: String, index: UInt32, receivedBytes: UInt64, sentBytes: UInt64) {
        self.name = name; self.index = index; self.receivedBytes = receivedBytes; self.sentBytes = sentBytes
    }
}

/// Matching-interface delta algorithm adapted from GlacierGlimmer/zmd-charge-plus-for-macos
/// b743c59, Customization/MacVariableProvider.cs (MIT). Adds reset/gap and observed-session guards.
public struct NetworkRateSampler {
    private var previous: [String: NetworkInterfaceCounter]?
    private var previousTime: Double?
    private var receivedBytes: UInt64 = 0
    private var sentBytes: UInt64 = 0
    public init() {}
    public mutating func reset() {
        previous = nil; previousTime = nil; receivedBytes = 0; sentBytes = 0
    }
    private func adding(_ a: UInt64, _ b: UInt64) -> UInt64 {
        let result = a.addingReportingOverflow(b)
        return result.overflow ? .max : result.partialValue
    }
    public mutating func sample(_ counters: [NetworkInterfaceCounter]?, at time: Double) -> NetworkTelemetry? {
        guard let counters, time.isFinite else {
            previous = nil; previousTime = nil; return nil
        }
        var current: [String: NetworkInterfaceCounter] = [:]
        for counter in counters { current[counter.name] = counter }
        defer { previous = current; previousTime = time }
        var down: Double?, up: Double?
        if let previous, let previousTime {
            let elapsed = time - previousTime
            if elapsed > 0, elapsed <= 60 {
                var rx = 0.0, tx = 0.0, matches = 0
                for (name, counter) in current {
                    guard let old = previous[name], old.index == counter.index,
                          counter.receivedBytes >= old.receivedBytes, counter.sentBytes >= old.sentBytes else { continue }
                    let received = counter.receivedBytes - old.receivedBytes
                    let sent = counter.sentBytes - old.sentBytes
                    rx += Double(received); tx += Double(sent); matches += 1
                    receivedBytes = adding(receivedBytes, received); sentBytes = adding(sentBytes, sent)
                }
                if matches > 0 { down = rx / elapsed; up = tx / elapsed }
            }
        }
        return NetworkTelemetry(downloadBytesPerSecond: down, uploadBytesPerSecond: up,
            receivedBytes: receivedBytes, sentBytes: sentBytes, interfaces: Array(current.keys))
    }
}
