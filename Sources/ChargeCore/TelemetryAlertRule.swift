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
    public var condition: TelemetryRuleCondition
    public var source: TelemetryStateSource?
    public var targetState: TelemetryState?
    public init(id: String, name: String = "ALERT", enabled: Bool = false, metric: TelemetryMetric = .cpuPercent,
                comparison: TelemetryComparison = .above, threshold: Double = 90,
                holdSeconds: Double = 0, cooldownSeconds: Double = 30,
                condition: TelemetryRuleCondition = .threshold, source: TelemetryStateSource? = nil,
                targetState: TelemetryState? = nil) {
        self.id = id; self.name = name; self.enabled = enabled; self.metric = metric
        self.comparison = comparison; self.threshold = threshold
        self.holdSeconds = holdSeconds; self.cooldownSeconds = cooldownSeconds
        self.condition = condition; self.source = source; self.targetState = targetState
        normalize()
    }
    public static func custom(name: String = "ALERT") -> Self { Self(id: UUID().uuidString, name: name) }
    public mutating func normalize() {
        id = ConfigurationTextLimit.identifier.bounded(id)
        name = ConfigurationTextLimit.name.bounded(name)
        if name.isEmpty { name = "ALERT" }
        if let targetState, source?.accepts(targetState) != true { self.targetState = nil }
        if !threshold.isFinite { threshold = 0 }
        holdSeconds = holdSeconds.isFinite ? min(300, max(0, holdSeconds)) : 0
        cooldownSeconds = cooldownSeconds.isFinite ? min(86400, max(10, cooldownSeconds)) : 30
    }
    private enum CodingKeys: String, CodingKey { case id, name, enabled, metric, comparison, threshold, holdSeconds, cooldownSeconds, condition, source, targetState }
    public init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        let condition = try v.decodeIfPresent(TelemetryRuleCondition.self, forKey: .condition) ?? .threshold
        self.init(id: try v.decodeIfPresent(String.self, forKey: .id) ?? "", name: try v.decodeIfPresent(String.self, forKey: .name) ?? "ALERT",
            enabled: try v.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
            metric: condition == .threshold ? try v.decode(TelemetryMetric.self, forKey: .metric) : try v.decodeIfPresent(TelemetryMetric.self, forKey: .metric) ?? .cpuPercent,
            comparison: try v.decodeIfPresent(TelemetryComparison.self, forKey: .comparison) ?? .above,
            threshold: try v.decodeIfPresent(Double.self, forKey: .threshold) ?? 90,
            holdSeconds: try v.decodeIfPresent(Double.self, forKey: .holdSeconds) ?? 0,
            cooldownSeconds: try v.decodeIfPresent(Double.self, forKey: .cooldownSeconds) ?? 30,
            condition: condition,
            source: try v.decodeIfPresent(TelemetryStateSource.self, forKey: .source),
            targetState: try v.decodeIfPresent(TelemetryState.self, forKey: .targetState))
    }
}

public struct TelemetryRuleEvaluator {
    private struct State {
        var rule: TelemetryAlertRule
        var armed: Bool
        var hasBaseline = true
        var observedState: TelemetryState?
        var pendingSince: Double?
        var lastFired: Double?
    }
    private var states: [String: State] = [:]
    private var previousTime: Double?
    public init() {}
    public mutating func reset() { states.removeAll(keepingCapacity: true); previousTime = nil }
    public mutating func evaluate(rules: [TelemetryAlertRule], snapshot: TelemetrySnapshot, at time: Double) -> [String] {
        var values: [TelemetryMetric: Double] = [:]
        var knownStates: [TelemetryStateSource: TelemetryState] = [:]
        for rule in rules.prefix(16) where rule.enabled {
            switch rule.condition {
            case .threshold: values[rule.metric] = rule.metric.value(in: snapshot)
            case .stateChange:
                if let source = rule.source { knownStates[source] = source.value(in: snapshot) }
            }
        }
        return evaluate(rules: rules, values: values, knownStates: knownStates, at: time)
    }
    /// Returns fired threshold rule IDs in configuration order; state sources are unavailable here.
    /// A cooldown-delayed numeric crossing may fire while that same excursion remains above/below threshold.
    public mutating func evaluate(rules: [TelemetryAlertRule], values: [TelemetryMetric: Double], at time: Double) -> [String] {
        evaluate(rules: rules, values: values, knownStates: [:], at: time)
    }
    private mutating func evaluate(rules: [TelemetryAlertRule], values: [TelemetryMetric: Double],
                                   knownStates: [TelemetryStateSource: TelemetryState], at time: Double) -> [String] {
        guard time.isFinite else { reset(); return [] }
        if let previousTime {
            if time <= previousTime { reset() }
            else if time - previousTime > 60 {
                // State gaps clear observations, not cooldowns. Keep legacy numeric gap semantics.
                states = states.filter { $0.value.rule.condition == .stateChange }.mapValues { previous in
                    var state = previous; state.observedState = nil; state.pendingSince = nil
                    return state
                }
            }
        }
        previousTime = time
        let active = rules.prefix(16).map { source -> TelemetryAlertRule in
            var rule = source; rule.normalize(); return rule
        }
        let ids = Set(active.filter(\.enabled).map(\.id))
        states = states.filter { ids.contains($0.key) }
        var fired: [String] = [], seen = Set<String>()
        for rule in active where rule.enabled && !rule.id.isEmpty && seen.insert(rule.id).inserted {
            if rule.condition == .stateChange {
                var state = states[rule.id].flatMap { $0.rule == rule ? $0 : nil } ?? State(rule: rule, armed: false)
                let current = rule.source.flatMap { knownStates[$0] }
                if evaluateStateChange(rule: rule, current: current, at: time, state: &state) { fired.append(rule.id) }
                states[rule.id] = state
                continue
            }
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

    private func evaluateStateChange(rule: TelemetryAlertRule, current: TelemetryState?,
                                     at time: Double, state: inout State) -> Bool {
        guard let current else { state.observedState = nil; state.pendingSince = nil; return false }
        guard let previous = state.observedState else { state.observedState = current; return false }
        if previous != current {
            state.observedState = current
            let matchesTarget = rule.targetState == nil || rule.targetState == current
            let cooldownOver = state.lastFired.map { time - $0 >= rule.cooldownSeconds } ?? true
            // A transition observed during cooldown is consumed immediately and never replayed.
            state.pendingSince = matchesTarget && cooldownOver ? time : nil
        }
        if let pending = state.pendingSince, time - pending >= rule.holdSeconds {
            state.pendingSince = nil; state.lastFired = time
            return true
        }
        return false
    }
}
