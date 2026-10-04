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

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case scale, duration, position, displayID, language, showPercentage, shortcutEnabled
        case shortcutKey, shortcutModifiers, lowBatteryAlert, fullBatteryAlert, lowPowerAlert
        case lowThreshold, ripplesEnabled
        case powerTelemetryEnabled, computeTelemetryEnabled, thermalTelemetryEnabled, thermalAlert
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
    }
}
