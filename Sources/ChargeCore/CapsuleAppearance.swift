import Foundation

public enum CapsuleAccent: String, Codable, CaseIterable {
    case theme, lime, amber, red
}

/// Ordered, numeric-only display conditions. Unknown readings never match.
public struct CapsuleColorCondition: Codable, Equatable {
    public var metric: TelemetryMetric
    public var comparison: TelemetryComparison
    public var threshold: Double
    public var accent: CapsuleAccent

    public init(metric: TelemetryMetric, comparison: TelemetryComparison,
                threshold: Double, accent: CapsuleAccent) {
        self.metric = metric; self.comparison = comparison
        self.threshold = threshold; self.accent = accent
    }

    public func matches(in snapshot: TelemetrySnapshot) -> Bool {
        guard threshold.isFinite, let value = metric.value(in: snapshot) else { return false }
        return comparison == .above ? value > threshold : value < threshold
    }
}
