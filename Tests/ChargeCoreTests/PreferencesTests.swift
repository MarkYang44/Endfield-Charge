import Foundation
import Testing
@testable import ChargeCore

struct PreferencesTests {
    @Test func legacyPreferencesKeepExistingSettings() throws {
        let data = Data("""
        {"scale":1.05,"duration":8,"position":"right","displayID":42,"language":"en",
         "showPercentage":false,"shortcutEnabled":true,"shortcutKey":"B",
         "lowBatteryAlert":false,"fullBatteryAlert":false,"lowPowerAlert":false,
         "lowThreshold":15,"ripplesEnabled":false}
        """.utf8)
        let value = try JSONDecoder().decode(Preferences.self, from: data)
        #expect(value.shortcutModifiers == [.control, .option])
        #expect(value.shortcutKey == "B")
        #expect(value.scale == 1.05)
        #expect(value.duration == 8)
        #expect(value.position == "right")
        #expect(value.displayID == 42)
        #expect(value.language == "en")
        #expect(!value.showPercentage)
        #expect(!value.lowBatteryAlert && !value.fullBatteryAlert && !value.lowPowerAlert)
        #expect(value.lowThreshold == 15)
        #expect(!value.ripplesEnabled)
    }

    @Test func customShortcutSurvivesSavingAndReloading() throws {
        var value = Preferences()
        value.shortcutKey = "E"
        value.shortcutModifiers = [.command, .shift]
        let reloaded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(value))
        #expect(reloaded.shortcutKey == "E")
        #expect(reloaded.shortcutModifiers == [.command, .shift])
        #expect(!reloaded.shortcutModifiers.contains(.control))
        #expect(!reloaded.shortcutModifiers.contains(.option))
    }
}
