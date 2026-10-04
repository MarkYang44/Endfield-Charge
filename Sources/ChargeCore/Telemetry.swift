import Foundation
import CoreFoundation

public enum ThermalLevel: String, Codable, Equatable, CaseIterable {
    case nominal, fair, serious, critical, unknown
}

public enum MemoryPressureLevel: String, Codable, Equatable, CaseIterable {
    case normal, warning, critical, unknown
}

public struct PowerTelemetry: Codable, Equatable {
    public var batteryWatts: Double?
    public var averageDischargeWatts: Double?
    public var adapterWatts: Int?
    public var cycleCount: Int?

    public init(batteryWatts: Double?, averageDischargeWatts: Double?, adapterWatts: Int?, cycleCount: Int?) {
        self.batteryWatts = batteryWatts; self.averageDischargeWatts = averageDischargeWatts
        self.adapterWatts = adapterWatts; self.cycleCount = cycleCount
    }
}

public struct ComputeTelemetry: Codable, Equatable {
    public var cpuFraction: Double?
    /// Approximation: active + wired + physical compressor pages; not Activity Monitor's "Memory Used".
    public var memoryUsedBytes: UInt64?
    public var memoryTotalBytes: UInt64
    public var compressedBytes: UInt64?
    public var swapUsedBytes: UInt64?
    public var pressure: MemoryPressureLevel

    public init(cpuFraction: Double?, memoryUsedBytes: UInt64?, memoryTotalBytes: UInt64,
                compressedBytes: UInt64?, swapUsedBytes: UInt64?, pressure: MemoryPressureLevel) {
        self.cpuFraction = cpuFraction; self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes; self.compressedBytes = compressedBytes
        self.swapUsedBytes = swapUsedBytes; self.pressure = pressure
    }
}

public struct TelemetrySnapshot: Codable, Equatable {
    public var sampledAt: Double
    public var battery: BatterySnapshot
    public var power: PowerTelemetry?
    public var compute: ComputeTelemetry?
    public var thermal: ThermalLevel?

    public init(sampledAt: Double, battery: BatterySnapshot, power: PowerTelemetry?,
                compute: ComputeTelemetry?, thermal: ThermalLevel?) {
        self.sampledAt = sampledAt; self.battery = battery; self.power = power
        self.compute = compute; self.thermal = thermal
    }
}

public struct CPUTicks: Equatable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }
}

public struct CPUTickSampler {
    private var previous: CPUTicks?
    public init() {}
    public mutating func reset() { previous = nil }

    public mutating func sample(_ ticks: CPUTicks) -> Double? {
        defer { previous = ticks }
        guard let previous, ticks.user >= previous.user, ticks.system >= previous.system,
              ticks.idle >= previous.idle, ticks.nice >= previous.nice else { return nil }
        // Convert individual differences before summing to avoid overflowing a tick total.
        let busy = Double(ticks.user - previous.user) + Double(ticks.system - previous.system)
            + Double(ticks.nice - previous.nice)
        let total = busy + Double(ticks.idle - previous.idle)
        guard total > 0 else { return nil }
        return busy / total
    }
}

public enum TelemetryMath {
    /// IOKit can expose a signed current as either native signed or 32/64-bit unsigned bits.
    /// NSNumber can widen an unsigned 32-bit value, so inspect the value as well as its sign.
    public static func signedMilliamps(_ number: NSNumber?) -> Int64? {
        guard let number, CFGetTypeID(number) != CFBooleanGetTypeID(),
              !["f", "d"].contains(String(cString: number.objCType)) else { return nil }
        let signed = number.int64Value
        if signed < 0 { return signed }
        let raw = number.uint64Value
        if raw <= UInt64(UInt32.max), raw > UInt64(Int32.max) {
            return Int64(Int32(bitPattern: UInt32(raw)))
        }
        return Int64(bitPattern: raw)
    }

    public static func batteryWatts(voltageMV: Int?, currentMA: Int64?) -> Double? {
        guard let voltageMV, voltageMV > 0, let currentMA else { return nil }
        return Double(voltageMV) * Double(currentMA) / 1_000_000
    }
}

public struct RecentDischargeAverage {
    private struct Interval {
        var start: Double
        var end: Double
        var watts: Double
    }
    private let window: Double
    private let maximumGap: Double
    private let maximumSamples: Int
    private var intervals: [Interval] = []
    private var previous: (time: Double, watts: Double)?

    public init(window: Double = 300, maximumGap: Double = 60, maximumSamples: Int = 150) {
        self.window = window.isFinite && window > 0 ? window : 300
        self.maximumGap = maximumGap.isFinite && maximumGap > 0 ? maximumGap : 60
        self.maximumSamples = max(1, maximumSamples)
    }

    public mutating func reset() { intervals.removeAll(keepingCapacity: true); previous = nil }

    /// Elapsed-time mean of prior observed watts held until the next reading, in positive W.
    /// Never integrates across charging, unknown readings, clock resets, or long sampling gaps.
    public mutating func sample(watts: Double?, at time: Double, discharging: Bool) -> Double? {
        guard discharging, let watts, watts.isFinite, watts <= 0, time.isFinite else {
            reset(); return nil
        }
        let current = (time: time, watts: -watts)
        defer { previous = current }
        guard let previous else { return nil }
        let elapsed = time - previous.time
        guard elapsed > 0, elapsed <= maximumGap else { reset(); return nil }
        intervals.append(Interval(start: previous.time, end: time, watts: previous.watts))
        let cutoff = time - window
        intervals.removeAll { $0.end <= cutoff }
        if intervals.count > maximumSamples { intervals.removeFirst(intervals.count - maximumSamples) }
        var energy = 0.0, duration = 0.0
        for interval in intervals {
            let seconds = interval.end - max(cutoff, interval.start)
            energy += seconds * interval.watts; duration += seconds
        }
        return duration > 0 ? energy / duration : nil
    }
}

public struct ThermalAlertState {
    private var peak: Int?
    public init() {}
    public mutating func reset() { peak = nil }

    public mutating func shouldAlert(_ level: ThermalLevel, enabled: Bool = true) -> Bool {
        let severity: Int
        switch level {
        case .nominal: severity = 0
        case .fair: severity = 1
        case .serious: severity = 2
        case .critical: severity = 3
        case .unknown: return false
        }
        guard let previous = peak else { peak = severity; return false }
        if severity < 2 { peak = severity; return false }
        peak = max(previous, severity)
        return enabled && severity > previous
    }
}
