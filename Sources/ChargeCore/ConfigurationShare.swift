import Foundation

public enum ConfigurationShareError: Error, Equatable, LocalizedError {
    case fileTooLarge, unsupportedFormat, unsupportedVersion, profileLimit, ruleLimit, invalidField(String)
    public var errorDescription: String? {
        switch self {
        case .fileTooLarge: return "Configuration exceeds 128 KiB."
        case .unsupportedFormat: return "Unrecognized configuration format."
        case .unsupportedVersion: return "Unsupported configuration schema version."
        case .profileLimit: return "Configuration exceeds \(ConfigurationLimits.maximumProfiles) capsules."
        case .ruleLimit: return "Configuration exceeds \(ConfigurationLimits.maximumRules) alert rules."
        case .invalidField(let field): return "Invalid configuration field: \(field)."
        }
    }
}

public enum ConfigurationImportMode: String, Codable { case merge, replace }

public struct ConfigurationImportSummary: Equatable {
    public var addedProfiles = 0
    public var reusedProfiles = 0
    public var replacedProfiles = 0
    public var addedRules = 0
    public var reusedRules = 0
    public var replacedRules = 0
    public var disabledRules = 0
    /// Ordered occurrences, including a missing selection and each missing queue reference.
    public var discardedReferences: [String] = []
}

public struct ConfigurationImportPreview: Equatable {
    public let preferences: Preferences
    public let summary: ConfigurationImportSummary
    public let profileIDMap: [String: String]
    public let ruleIDMap: [String: String]
}

/// Portable configuration only. Strict decoding deliberately bypasses legacy preference migration.
public struct ConfigurationShare: Codable, Equatable {
    public static let maximumFileBytes = 131_072
    public static let formatIdentifier = "endfield.configuration"
    public static let currentSchemaVersion = 1
    public var format: String
    public var schemaVersion: Int
    public var profiles: [CapsuleProfile]
    public var rules: [TelemetryAlertRule]
    public var selectedProfileID: String
    public var playback: CapsulePlayback

    public init(preferences: Preferences) throws {
        format = Self.formatIdentifier; schemaVersion = Self.currentSchemaVersion
        profiles = preferences.capsuleProfiles; rules = preferences.telemetryAlertRules
        selectedProfileID = preferences.selectedCapsuleID; playback = preferences.playback
        try validate()
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumFileBytes else { throw ConfigurationShareError.fileTooLarge }
        return try JSONDecoder().decode(Self.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(self)
        guard bytes.count <= Self.maximumFileBytes else { throw ConfigurationShareError.fileTooLarge }
        return bytes
    }

    public func validate() throws {
        guard format == Self.formatIdentifier else { throw ConfigurationShareError.unsupportedFormat }
        guard schemaVersion == Self.currentSchemaVersion else { throw ConfigurationShareError.unsupportedVersion }
        guard profiles.count <= ConfigurationLimits.maximumProfiles else { throw ConfigurationShareError.profileLimit }
        guard rules.count <= ConfigurationLimits.maximumRules else { throw ConfigurationShareError.ruleLimit }
        var ids = Set<String>()
        for (i, profile) in profiles.enumerated() {
            let path = "profiles[\(i)]"
            try Self.text(profile.id, limit: .identifier, path: path + ".id")
            try Self.text(profile.title, limit: .name, path: path + ".title")
            guard ids.insert(profile.id).inserted else { throw ConfigurationShareError.invalidField(path + ".id.duplicate") }
            guard profile.referenceMaximum.isFinite && profile.referenceMaximum > 0 else { throw ConfigurationShareError.invalidField(path + ".referenceMaximum") }
            guard profile.colorConditions.count <= ConfigurationLimits.maximumColorConditions else { throw ConfigurationShareError.invalidField(path + ".colorConditions.count") }
            for condition in profile.colorConditions where !condition.threshold.isFinite {
                throw ConfigurationShareError.invalidField(path + ".colorConditions.threshold")
            }
        }
        ids.removeAll()
        for (i, rule) in rules.enumerated() {
            let path = "rules[\(i)]"
            try Self.text(rule.id, limit: .identifier, path: path + ".id")
            try Self.text(rule.name, limit: .name, path: path + ".name")
            guard ids.insert(rule.id).inserted else { throw ConfigurationShareError.invalidField(path + ".id.duplicate") }
            guard rule.threshold.isFinite else { throw ConfigurationShareError.invalidField(path + ".threshold") }
            guard rule.holdSeconds.isFinite && (0...300).contains(rule.holdSeconds) else { throw ConfigurationShareError.invalidField(path + ".holdSeconds") }
            guard rule.cooldownSeconds.isFinite && (10...86400).contains(rule.cooldownSeconds) else { throw ConfigurationShareError.invalidField(path + ".cooldownSeconds") }
            if rule.condition == .stateChange && rule.source == nil { throw ConfigurationShareError.invalidField(path + ".source") }
            if let target = rule.targetState, rule.source?.accepts(target) != true { throw ConfigurationShareError.invalidField(path + ".targetState") }
        }
        try Self.text(selectedProfileID, limit: .identifier, path: "selectedProfileID")
        guard playback.profileIDs.count <= ConfigurationLimits.maximumProfiles else { throw ConfigurationShareError.invalidField("playback.profileIDs.count") }
        ids.removeAll()
        for id in playback.profileIDs {
            try Self.text(id, limit: .identifier, path: "playback.profileIDs")
            guard ids.insert(id).inserted else { throw ConfigurationShareError.invalidField("playback.profileIDs.duplicate") }
        }
        guard playback.intervalSeconds.isFinite && (10...600).contains(playback.intervalSeconds) else { throw ConfigurationShareError.invalidField("playback.intervalSeconds") }
    }

    private static func text(_ text: String, limit: ConfigurationTextLimit, path: String) throws {
        guard limit.accepted(text) == text else { throw ConfigurationShareError.invalidField(path) }
    }

    public func preview(mode: ConfigurationImportMode, local: Preferences) throws -> ConfigurationImportPreview {
        try validate()
        // Reject invalid/overflowing local input rather than letting Preferences.encode truncate the result.
        _ = try Self(preferences: local)
        var result = local
        var summary = ConfigurationImportSummary()
        var profileMap: [String: String] = [:], ruleMap: [String: String] = [:]
        var mergedProfiles = mode == .merge ? local.capsuleProfiles : []
        var usedProfileIDs = Set(local.capsuleProfiles.map(\.id) + profiles.map(\.id))
        for source in profiles {
            let builtin = CapsuleProfile.defaults.first { $0.id == source.id }
            let modifiedBuiltin = builtin.map { $0 != source } ?? false
            if let same = mergedProfiles.first(where: { existing in
                if modifiedBuiltin && CapsuleProfile.defaults.contains(where: { $0.id == existing.id }) { return false }
                var candidate = source; candidate.id = existing.id; return candidate == existing
            }) {
                profileMap[source.id] = same.id; summary.reusedProfiles += 1
                continue
            }
            var imported = source
            if modifiedBuiltin || mergedProfiles.contains(where: { $0.id == source.id }) {
                imported.id = Self.freshID(prefix: "import.profile.", used: &usedProfileIDs)
            }
            profileMap[source.id] = imported.id
            mergedProfiles.append(imported); summary.addedProfiles += 1
        }
        if !mergedProfiles.contains(where: { $0.id == CapsuleProfile.batteryID }) {
            mergedProfiles.insert(CapsuleProfile.defaults[0], at: 0)
        }
        guard mergedProfiles.count <= ConfigurationLimits.maximumProfiles else { throw ConfigurationShareError.profileLimit }
        var mergedRules = mode == .merge ? local.telemetryAlertRules : []
        var usedRuleIDs = Set(local.telemetryAlertRules.map(\.id) + rules.map(\.id))
        for source in rules {
            if let same = mergedRules.first(where: { existing in
                var candidate = source; candidate.id = existing.id; candidate.enabled = existing.enabled
                return candidate == existing
            }) {
                ruleMap[source.id] = same.id; summary.reusedRules += 1; continue
            }
            var imported = source
            if mergedRules.contains(where: { $0.id == imported.id }) { imported.id = Self.freshID(prefix: "import.rule.", used: &usedRuleIDs) }
            imported.enabled = false
            ruleMap[source.id] = imported.id; mergedRules.append(imported)
            summary.addedRules += 1; summary.disabledRules += 1
        }
        guard mergedRules.count <= ConfigurationLimits.maximumRules else { throw ConfigurationShareError.ruleLimit }
        result.capsuleProfiles = mergedProfiles; result.telemetryAlertRules = mergedRules
        let selected = profileMap[selectedProfileID]
        if selected == nil { summary.discardedReferences.append(selectedProfileID) }
        var queue: [String] = []
        for id in playback.profileIDs {
            if let mapped = profileMap[id] { if !queue.contains(mapped) { queue.append(mapped) } }
            else { summary.discardedReferences.append(id) }
        }
        if mode == .replace {
            result.selectedCapsuleID = selected ?? CapsuleProfile.batteryID
            result.playback = CapsulePlayback(profileIDs: queue, intervalSeconds: playback.intervalSeconds)
            summary.replacedProfiles = local.capsuleProfiles.count
            summary.replacedRules = local.telemetryAlertRules.count
        } else {
            for id in queue where !result.playback.profileIDs.contains(id) { result.playback.profileIDs.append(id) }
            guard result.playback.profileIDs.count <= ConfigurationLimits.maximumProfiles else { throw ConfigurationShareError.invalidField("playback.profileIDs.count") }
        }
        _ = try Self(preferences: result)
        return ConfigurationImportPreview(preferences: result, summary: summary, profileIDMap: profileMap, ruleIDMap: ruleMap)
    }

    private static func freshID(prefix: String, used: inout Set<String>) -> String {
        var index = 1
        while !used.insert(prefix + String(index)).inserted { index += 1 }
        return prefix + String(index)
    }

    private enum CodingKeys: String, CodingKey { case format, schemaVersion, profiles, rules, selectedProfileID, playback }
    public init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        format = try v.decode(String.self, forKey: .format)
        schemaVersion = try v.decode(Int.self, forKey: .schemaVersion)
        profiles = try v.decode([RawProfile].self, forKey: .profiles).map(\.value)
        rules = try v.decode([RawRule].self, forKey: .rules).map(\.value)
        selectedProfileID = try v.decode(String.self, forKey: .selectedProfileID)
        playback = try v.decode(RawPlayback.self, forKey: .playback).value
        try validate()
    }
    public func encode(to encoder: Encoder) throws {
        try validate()
        var v = encoder.container(keyedBy: CodingKeys.self)
        try v.encode(format, forKey: .format); try v.encode(schemaVersion, forKey: .schemaVersion)
        try v.encode(profiles, forKey: .profiles); try v.encode(rules, forKey: .rules)
        try v.encode(selectedProfileID, forKey: .selectedProfileID); try v.encode(playback, forKey: .playback)
    }
}

// Synthesized raw decoding neither clamps nor drops malformed entries. Assigning raw fields avoids
// the deliberately forgiving initializers used for on-device preference migration.
private struct RawProfile: Decodable {
    let id: String, title: String
    let primaryMetric: TelemetryMetric
    let secondaryMetric: TelemetryMetric?, ringMetric: TelemetryMetric?
    let referenceMaximum: Double
    let colorConditions: [CapsuleColorCondition]
    var value: CapsuleProfile {
        var p = CapsuleProfile.defaults[0]
        p.id = id; p.title = title; p.primaryMetric = primaryMetric; p.secondaryMetric = secondaryMetric
        p.ringMetric = ringMetric; p.referenceMaximum = referenceMaximum; p.colorConditions = colorConditions
        return p
    }
}
private struct RawRule: Decodable {
    let id: String, name: String
    let enabled: Bool
    let metric: TelemetryMetric
    let comparison: TelemetryComparison
    let threshold: Double, holdSeconds: Double, cooldownSeconds: Double
    let condition: TelemetryRuleCondition
    let source: TelemetryStateSource?
    let targetState: TelemetryState?
    var value: TelemetryAlertRule {
        var r = TelemetryAlertRule(id: "raw")
        r.id = id; r.name = name; r.enabled = enabled; r.metric = metric; r.comparison = comparison
        r.threshold = threshold; r.holdSeconds = holdSeconds; r.cooldownSeconds = cooldownSeconds
        r.condition = condition; r.source = source; r.targetState = targetState
        return r
    }
}
private struct RawPlayback: Decodable {
    let persistent: Bool, rotationEnabled: Bool
    let profileIDs: [String]
    let intervalSeconds: Double
    var value: CapsulePlayback {
        CapsulePlayback(persistent: persistent, rotationEnabled: rotationEnabled, profileIDs: profileIDs, intervalSeconds: intervalSeconds)
    }
}
