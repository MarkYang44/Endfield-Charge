import Foundation

public enum TelemetryRuleCondition: String, Codable, CaseIterable {
    case threshold, stateChange
}

/// A status value keeps its source type, even when two sources share a label such as critical.
public enum TelemetryState: Codable, Equatable {
    case thermal(ThermalLevel)
    case memoryPressure(MemoryPressureLevel)

    public var source: TelemetryStateSource {
        switch self {
        case .thermal: return .thermal
        case .memoryPressure: return .memoryPressure
        }
    }

    public var isKnown: Bool {
        switch self {
        case .thermal(let level): return level != .unknown
        case .memoryPressure(let level): return level != .unknown
        }
    }
}

public enum TelemetryStateSource: String, Codable, CaseIterable {
    case thermal, memoryPressure

    /// Also usable by strict import validation before forgiving preference normalization.
    public func accepts(_ state: TelemetryState) -> Bool { state.source == self && state.isKnown }

    public func value(in snapshot: TelemetrySnapshot) -> TelemetryState? {
        let value: TelemetryState?
        switch self {
        case .thermal: value = snapshot.thermal.map(TelemetryState.thermal)
        case .memoryPressure: value = snapshot.compute.map { .memoryPressure($0.pressure) }
        }
        return value.flatMap { accepts($0) ? $0 : nil }
    }
}
