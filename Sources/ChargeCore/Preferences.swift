import Foundation

public enum ShortcutModifier: String, Codable, CaseIterable {
    case command, control, option, shift

    public var symbol: String {
        switch self {
        case .command: return "⌘"
        case .control: return "⌃"
        case .option: return "⌥"
        case .shift: return "⇧"
        }
    }
}

public struct Preferences: Codable, Equatable {
    public var scale = 0.8
    public var duration = 6.0
    public var position = "center"
    public var displayID: UInt32 = 0
    public var language = "system"
    public var showPercentage = true
    public var shortcutEnabled = true
    public var shortcutKey = "H"
    public var shortcutModifiers: Set<ShortcutModifier> = [.control, .option]
    public var lowBatteryAlert = true
    public var fullBatteryAlert = true
    public var lowPowerAlert = true
    public var lowThreshold = 20
    public var ripplesEnabled = true
    public var powerTelemetryEnabled = true
    public var computeTelemetryEnabled = true
    public var thermalTelemetryEnabled = true
    public var thermalAlert = true
    public var networkTelemetryEnabled = true
    public var storageTelemetryEnabled = true
    public var capsuleProfiles = CapsuleProfile.defaults
    public var selectedCapsuleID = CapsuleProfile.batteryID
    public var telemetryAlertRules: [TelemetryAlertRule] = []
    public var playback = CapsulePlayback()

    public init() {}

    public mutating func normalizeTelemetryConfiguration() {
        var seen = Set<String>()
        capsuleProfiles = capsuleProfiles.prefix(12).compactMap { source in
            var profile = source; profile.normalize()
            return !profile.id.isEmpty && seen.insert(profile.id).inserted ? profile : nil
        }
        if !capsuleProfiles.contains(where: { $0.id == CapsuleProfile.batteryID }) {
            if capsuleProfiles.count == 12 { capsuleProfiles.removeLast() }
            capsuleProfiles.insert(CapsuleProfile.defaults[0], at: 0)
        }
        if !capsuleProfiles.contains(where: { $0.id == selectedCapsuleID }) { selectedCapsuleID = CapsuleProfile.batteryID }
        playback.normalize(profiles: capsuleProfiles)
        seen.removeAll(keepingCapacity: true)
        telemetryAlertRules = telemetryAlertRules.prefix(16).compactMap { source in
            var rule = source; rule.normalize()
            return !rule.id.isEmpty && seen.insert(rule.id).inserted ? rule : nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case scale, duration, position, displayID, language, showPercentage, shortcutEnabled
        case shortcutKey, shortcutModifiers, lowBatteryAlert, fullBatteryAlert, lowPowerAlert
        case lowThreshold, ripplesEnabled
        case powerTelemetryEnabled, computeTelemetryEnabled, thermalTelemetryEnabled, thermalAlert
        case networkTelemetryEnabled, storageTelemetryEnabled, capsuleProfiles, selectedCapsuleID, telemetryAlertRules, playback
    }

    public func encode(to encoder: Encoder) throws {
        var value = self
        value.normalizeTelemetryConfiguration()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(value.scale, forKey: .scale)
        try values.encode(value.duration, forKey: .duration)
        try values.encode(value.position, forKey: .position)
        try values.encode(value.displayID, forKey: .displayID)
        try values.encode(value.language, forKey: .language)
        try values.encode(value.showPercentage, forKey: .showPercentage)
        try values.encode(value.shortcutEnabled, forKey: .shortcutEnabled)
        try values.encode(value.shortcutKey, forKey: .shortcutKey)
        try values.encode(value.shortcutModifiers, forKey: .shortcutModifiers)
        try values.encode(value.lowBatteryAlert, forKey: .lowBatteryAlert)
        try values.encode(value.fullBatteryAlert, forKey: .fullBatteryAlert)
        try values.encode(value.lowPowerAlert, forKey: .lowPowerAlert)
        try values.encode(value.lowThreshold, forKey: .lowThreshold)
        try values.encode(value.ripplesEnabled, forKey: .ripplesEnabled)
        try values.encode(value.powerTelemetryEnabled, forKey: .powerTelemetryEnabled)
        try values.encode(value.computeTelemetryEnabled, forKey: .computeTelemetryEnabled)
        try values.encode(value.thermalTelemetryEnabled, forKey: .thermalTelemetryEnabled)
        try values.encode(value.thermalAlert, forKey: .thermalAlert)
        try values.encode(value.networkTelemetryEnabled, forKey: .networkTelemetryEnabled)
        try values.encode(value.storageTelemetryEnabled, forKey: .storageTelemetryEnabled)
        try values.encode(value.capsuleProfiles, forKey: .capsuleProfiles)
        try values.encode(value.selectedCapsuleID, forKey: .selectedCapsuleID)
        try values.encode(value.telemetryAlertRules, forKey: .telemetryAlertRules)
        try values.encode(value.playback, forKey: .playback)
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        scale = try values.decodeIfPresent(Double.self, forKey: .scale) ?? scale
        duration = try values.decodeIfPresent(Double.self, forKey: .duration) ?? duration
        position = try values.decodeIfPresent(String.self, forKey: .position) ?? position
        displayID = try values.decodeIfPresent(UInt32.self, forKey: .displayID) ?? displayID
        language = try values.decodeIfPresent(String.self, forKey: .language) ?? language
        showPercentage = try values.decodeIfPresent(Bool.self, forKey: .showPercentage) ?? showPercentage
        shortcutEnabled = try values.decodeIfPresent(Bool.self, forKey: .shortcutEnabled) ?? shortcutEnabled
        shortcutKey = try values.decodeIfPresent(String.self, forKey: .shortcutKey) ?? shortcutKey
        shortcutModifiers = try values.decodeIfPresent(Set<ShortcutModifier>.self, forKey: .shortcutModifiers) ?? shortcutModifiers
        lowBatteryAlert = try values.decodeIfPresent(Bool.self, forKey: .lowBatteryAlert) ?? lowBatteryAlert
        fullBatteryAlert = try values.decodeIfPresent(Bool.self, forKey: .fullBatteryAlert) ?? fullBatteryAlert
        lowPowerAlert = try values.decodeIfPresent(Bool.self, forKey: .lowPowerAlert) ?? lowPowerAlert
        lowThreshold = try values.decodeIfPresent(Int.self, forKey: .lowThreshold) ?? lowThreshold
        ripplesEnabled = try values.decodeIfPresent(Bool.self, forKey: .ripplesEnabled) ?? ripplesEnabled
        powerTelemetryEnabled = try values.decodeIfPresent(Bool.self, forKey: .powerTelemetryEnabled) ?? powerTelemetryEnabled
        computeTelemetryEnabled = try values.decodeIfPresent(Bool.self, forKey: .computeTelemetryEnabled) ?? computeTelemetryEnabled
        thermalTelemetryEnabled = try values.decodeIfPresent(Bool.self, forKey: .thermalTelemetryEnabled) ?? thermalTelemetryEnabled
        thermalAlert = try values.decodeIfPresent(Bool.self, forKey: .thermalAlert) ?? thermalAlert
        networkTelemetryEnabled = (try? values.decodeIfPresent(Bool.self, forKey: .networkTelemetryEnabled)) ?? networkTelemetryEnabled
        storageTelemetryEnabled = (try? values.decodeIfPresent(Bool.self, forKey: .storageTelemetryEnabled)) ?? storageTelemetryEnabled
        capsuleProfiles = (try? values.decodeIfPresent(BoundedProfiles.self, forKey: .capsuleProfiles))?.items ?? capsuleProfiles
        selectedCapsuleID = (try? values.decodeIfPresent(String.self, forKey: .selectedCapsuleID)) ?? selectedCapsuleID
        telemetryAlertRules = (try? values.decodeIfPresent(BoundedRules.self, forKey: .telemetryAlertRules))?.items ?? telemetryAlertRules
        playback = (try? values.decodeIfPresent(CapsulePlayback.self, forKey: .playback)) ?? playback
        normalizeTelemetryConfiguration()
    }
}

// Decode a bounded prefix while skipping malformed entries without discarding valid neighbors.
private struct BoundedProfiles: Decodable {
    var items: [CapsuleProfile] = []
    init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        for _ in 0..<12 where !values.isAtEnd {
            let entry = try values.superDecoder()
            if let value = try? CapsuleProfile(from: entry) { items.append(value) }
        }
    }
}
private struct BoundedRules: Decodable {
    var items: [TelemetryAlertRule] = []
    init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        for _ in 0..<16 where !values.isAtEnd {
            let entry = try values.superDecoder()
            if let value = try? TelemetryAlertRule(from: entry) { items.append(value) }
        }
    }
}
