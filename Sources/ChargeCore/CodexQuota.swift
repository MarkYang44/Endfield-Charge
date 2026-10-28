import Foundation

/// Only the two supported Codex account windows are retained; no account identifiers or raw response.
public struct CodexQuotaWindow: Codable, Equatable {
    public let remainingPercent: Double
    public let resetsAt: Double?

    public init?(usedPercent: Double, resetsAt: Double?) {
        guard usedPercent.isFinite else { return nil }
        remainingPercent = min(100, max(0, 100 - usedPercent))
        self.resetsAt = resetsAt.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }
}

public struct CodexQuotaSnapshot: Codable, Equatable {
    public var fiveHour: CodexQuotaWindow?
    public var weekly: CodexQuotaWindow?
    public init(fiveHour: CodexQuotaWindow?, weekly: CodexQuotaWindow?) {
        self.fiveHour = fiveHour; self.weekly = weekly
    }
    public func window(for metric: TelemetryMetric) -> CodexQuotaWindow? {
        switch metric {
        case .codexFiveHourRemainingPercent: return fiveHour
        case .codexWeeklyRemainingPercent: return weekly
        default: return nil
        }
    }
    /// Parses the documented account/rateLimits/read result, never other feature buckets.
    public static func parse(_ data: Data) throws -> Self {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let keyed = root["rateLimitsByLimitId"] as? [String: Any]
        let legacy = root["rateLimits"] as? [String: Any]
        let compatibleLegacy = legacy.flatMap { bucket -> [String: Any]? in
            guard bucket["limitId"] == nil || bucket["limitId"] as? String == "codex" else { return nil }
            return bucket
        }
        guard let bucket = keyed?["codex"] as? [String: Any] ?? compatibleLegacy else {
            return Self(fiveHour: nil, weekly: nil)
        }
        var result = Self(fiveHour: nil, weekly: nil)
        for key in ["primary", "secondary"] {
            guard let window = bucket[key] as? [String: Any],
                  let duration = number(window["windowDurationMins"]),
                  let used = number(window["usedPercent"]),
                  let value = CodexQuotaWindow(usedPercent: used, resetsAt: number(window["resetsAt"])) else { continue }
            if duration == 300 { result.fiveHour = value }
            if duration == 10080 { result.weekly = value }
        }
        return result
    }
    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }
}

public enum CodexQuotaCountdown {
    public static func text(resetsAt: Double?, at now: Double, chinese: Bool) -> String {
        guard let resetsAt, resetsAt.isFinite, now.isFinite else { return "—" }
        let seconds = resetsAt - now
        guard seconds > 0 else { return chinese ? "待重置" : "Reset due" }
        guard seconds >= 60 else { return chinese ? "<1分" : "<1m" }
        // Bound before converting untrusted timestamps to Int.
        let minutes = Int(min(seconds / 60, 525_600_000))
        if minutes >= 1440 { return chinese ? "\(minutes / 1440)天 \(minutes % 1440 / 60)时" : "\(minutes / 1440)d \(minutes % 1440 / 60)h" }
        if minutes >= 60 { return chinese ? "\(minutes / 60)时 \(minutes % 60)分" : "\(minutes / 60)h \(minutes % 60)m" }
        return chinese ? "\(minutes)分" : "\(minutes)m"
    }
}

extension Preferences {
    /// Explicit opt-in only: these are ordinary deletable/editable custom profiles, not defaults.
    @discardableResult public mutating func selectCodexQuotaPreset(_ metric: TelemetryMetric) -> String? {
        guard metric.isCodexQuota else { return nil }
        let id = "preset." + metric.rawValue
        if !capsuleProfiles.contains(where: { $0.id == id }) {
            guard capsuleProfiles.count < ConfigurationLimits.maximumProfiles else { return nil }
            capsuleProfiles.append(CapsuleProfile(id: id,
                title: metric == .codexFiveHourRemainingPercent ? "CODEX 5H" : "CODEX WEEK",
                primaryMetric: metric, ringMetric: metric, referenceMaximum: 100))
        }
        selectedCapsuleID = id
        return id
    }
}
