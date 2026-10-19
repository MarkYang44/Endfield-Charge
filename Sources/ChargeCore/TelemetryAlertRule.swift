import Foundation

public enum TelemetryComparison: String, Codable, CaseIterable { case above, below }

/// Typed rule normalization/evaluation adapted from GlacierGlimmer/zmd-charge-plus-for-macos
/// b743c59, Customization/HudTriggerRule.cs (MIT). Adds recovery, hold, excursion and gap guards.
public struct TelemetryAlertRule: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var enabled: Bool
    public var metric: TelemetryMetric
    public var comparison: TelemetryComparison
    public var threshold: Double
    public var holdSeconds: Double
    public var cooldownSeconds: Double
    public init(id: String, name: String = "ALERT", enabled: Bool = false, metric: TelemetryMetric = .cpuPercent,
                comparison: TelemetryComparison = .above, threshold: Double = 90,
                holdSeconds: Double = 0, cooldownSeconds: Double = 30) {
        self.id = id; self.name = name; self.enabled = enabled; self.metric = metric
        self.comparison = comparison; self.threshold = threshold
        self.holdSeconds = holdSeconds; self.cooldownSeconds = cooldownSeconds
        normalize()
    }
    public static func custom(name: String = "ALERT") -> Self { Self(id: UUID().uuidString, name: name) }
    public mutating func normalize() {
        id = ConfigurationTextLimit.identifier.bounded(id)
        name = ConfigurationTextLimit.name.bounded(name)
        if name.isEmpty { name = "ALERT" }
        if !threshold.isFinite { threshold = 0 }
        holdSeconds = holdSeconds.isFinite ? min(300, max(0, holdSeconds)) : 0
        cooldownSeconds = cooldownSeconds.isFinite ? min(86400, max(10, cooldownSeconds)) : 30
    }
    private enum CodingKeys: String, CodingKey { case id, name, enabled, metric, comparison, threshold, holdSeconds, cooldownSeconds }
    public init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try v.decodeIfPresent(String.self, forKey: .id) ?? "", name: try v.decodeIfPresent(String.self, forKey: .name) ?? "ALERT",
            enabled: try v.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
            metric: try v.decode(TelemetryMetric.self, forKey: .metric),
            comparison: try v.decodeIfPresent(TelemetryComparison.self, forKey: .comparison) ?? .above,
            threshold: try v.decodeIfPresent(Double.self, forKey: .threshold) ?? 90,
            holdSeconds: try v.decodeIfPresent(Double.self, forKey: .holdSeconds) ?? 0,
            cooldownSeconds: try v.decodeIfPresent(Double.self, forKey: .cooldownSeconds) ?? 30)
    }
}

public struct TelemetryRuleEvaluator {
    private struct State {
        var rule: TelemetryAlertRule
        var armed: Bool
        var hasBaseline = true
        var pendingSince: Double?
        var lastFired: Double?
    }
    private var states: [String: State] = [:]
    private var previousTime: Double?
    public init() {}
    public mutating func reset() { states.removeAll(keepingCapacity: true); previousTime = nil }
    public mutating func evaluate(rules: [TelemetryAlertRule], snapshot: TelemetrySnapshot, at time: Double) -> [String] {
        var values: [TelemetryMetric: Double] = [:]
        for metric in Set(rules.prefix(16).filter(\.enabled).map(\.metric)) { values[metric] = metric.value(in: snapshot) }
        return evaluate(rules: rules, values: values, at: time)
    }
    /// Returns fired rule IDs, in configuration order. Clock must be monotonic uptime seconds.
    /// A cooldown-delayed crossing may fire while that same excursion remains above/below threshold.
    public mutating func evaluate(rules: [TelemetryAlertRule], values: [TelemetryMetric: Double], at time: Double) -> [String] {
        guard time.isFinite else { reset(); return [] }
        if let previousTime, time <= previousTime || time - previousTime > 60 { reset() }
        previousTime = time
        let active = rules.prefix(16).map { source -> TelemetryAlertRule in
            var rule = source; rule.normalize(); return rule
        }
        let ids = Set(active.filter(\.enabled).map(\.id))
        states = states.filter { ids.contains($0.key) }
        var fired: [String] = [], seen = Set<String>()
        for rule in active where rule.enabled && !rule.id.isEmpty && seen.insert(rule.id).inserted {
            guard let value = values[rule.metric], value.isFinite else {
                // Unknown values clear crossing/hold history but cannot bypass an existing cooldown.
                if var state = states[rule.id], state.rule == rule {
                    state.hasBaseline = false; state.armed = false; state.pendingSince = nil
                    states[rule.id] = state
                } else { states.removeValue(forKey: rule.id) }
                continue
            }
            let bad = rule.comparison == .above ? value > rule.threshold : value < rule.threshold
            guard var state = states[rule.id], state.rule == rule else {
                states[rule.id] = State(rule: rule, armed: !bad); continue
            }
            if !state.hasBaseline {
                state.hasBaseline = true; state.armed = !bad; state.pendingSince = nil
            } else if !bad { state.armed = true; state.pendingSince = nil }
            else if state.armed {
                if state.pendingSince == nil { state.pendingSince = time }
                if let pending = state.pendingSince, time - pending >= rule.holdSeconds,
                   state.lastFired.map({ time - $0 >= rule.cooldownSeconds }) ?? true {
                    fired.append(rule.id); state.lastFired = time
                    state.armed = false; state.pendingSince = nil
                }
            }
            states[rule.id] = state
        }
        return fired
    }
}
