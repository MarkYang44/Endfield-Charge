import Foundation
import Testing
@testable import ChargeCore

struct TelemetryPreferenceTests {
    @Test func legacyPreferencesKeepAllValuesAndDefaultTelemetryOn() throws {
        let old = Data(#"{"scale":0.6,"duration":4,"language":"zh","showPercentage":false,"shortcutKey":"E","shortcutModifiers":["command","shift"]}"#.utf8)
        let value = try JSONDecoder().decode(Preferences.self, from: old)
        #expect(value.scale == 0.6 && value.duration == 4 && !value.showPercentage)
        #expect(value.shortcutKey == "E" && value.shortcutModifiers == [.command, .shift])
        #expect(value.powerTelemetryEnabled && value.computeTelemetryEnabled && value.thermalTelemetryEnabled && value.thermalAlert)
    }

    @Test func disabledTelemetrySurvivesRoundTrip() throws {
        var value = Preferences()
        value.powerTelemetryEnabled = false; value.computeTelemetryEnabled = false
        value.thermalTelemetryEnabled = false; value.thermalAlert = false
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(value))
        #expect(decoded == value)
        #expect(!decoded.powerTelemetryEnabled && !decoded.computeTelemetryEnabled && !decoded.thermalTelemetryEnabled && !decoded.thermalAlert)
    }
}
