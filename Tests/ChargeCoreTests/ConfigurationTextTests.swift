import Foundation
import Testing
@testable import ChargeCore

struct ConfigurationTextTests {
    let familyName = String(repeating: "👨‍👩‍👧‍👦", count: 32)
    let hugeGrapheme = "e" + String(repeating: "\u{301}", count: 600)

    @Test func validMultiscalarNamesRemainWhole() {
        #expect(familyName.count == 32 && familyName.utf8.count == 800)
        #expect(CapsuleProfile(id: "p", title: familyName, primaryMetric: .cpuPercent).title == familyName)
        #expect(TelemetryAlertRule(id: "r", name: familyName).name == familyName)
    }

    @Test func nameByteLimitKeepsWholeGraphemesAndExistingFallbacks() throws {
        let profile = CapsuleProfile(id: "p", title: "OK" + hugeGrapheme, primaryMetric: .cpuPercent)
        let rule = TelemetryAlertRule(id: "r", name: hugeGrapheme)
        #expect(profile.title == "OK")
        #expect(rule.name == "ALERT")
        #expect(CapsuleProfile(id: "p", title: hugeGrapheme, primaryMetric: .cpuPercent).title == "CUSTOM")
        let persisted = try JSONEncoder().encode(["id": "r", "name": "OK" + hugeGrapheme, "metric": "cpuPercent"])
        #expect(try JSONDecoder().decode(TelemetryAlertRule.self, from: persisted).name == "OK")
        let boundary = "e" + String(repeating: "\u{301}", count: 511)
        #expect(TelemetryAlertRule(id: "r", name: boundary + "x").name == boundary + "x")
        #expect(TelemetryAlertRule(id: "r", name: boundary + "xy").name == boundary + "x")
    }

    @Test func identifiersHonorCharacterAndByteBounds() {
        let families = String(repeating: "👨‍👩‍👧‍👦", count: 64)
        #expect(CapsuleProfile(id: families, title: "p", primaryMetric: .cpuPercent).id == String(families.prefix(10)))
        #expect(TelemetryAlertRule(id: " \(families) ").id == String(families.prefix(10)))
        #expect(TelemetryAlertRule(id: hugeGrapheme).id.isEmpty)
        #expect(TelemetryAlertRule(id: String(repeating: "a", count: 65)).id.count == 64)
    }

    @Test func mutatedPreferencesEncodeANormalizedCopy() throws {
        var preferences = Preferences()
        preferences.capsuleProfiles[0].title = "OK" + hugeGrapheme
        var rule = TelemetryAlertRule(id: "r")
        rule.name = hugeGrapheme; rule.id = String(repeating: "👨‍👩‍👧‍👦", count: 64)
        preferences.telemetryAlertRules = [rule]
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        #expect(decoded.capsuleProfiles[0].title == "OK")
        #expect(decoded.telemetryAlertRules[0].name == "ALERT")
        #expect(decoded.telemetryAlertRules[0].id.utf8.count <= 256)
        #expect(preferences.capsuleProfiles[0].title == "OK" + hugeGrapheme)
        #expect(preferences.telemetryAlertRules[0] == rule)
    }

    @Test func maximumConfigurationAndSnapshotFitSharedWireBudget() throws {
        let name = "e" + String(repeating: "\u{301}", count: 511) + "x"
        let idSuffix = String(repeating: "👨‍👩‍👧‍👦", count: 10)
        var preferences = Preferences()
        preferences.capsuleProfiles = (0..<12).map { index in
            CapsuleProfile(id: index == 0 ? CapsuleProfile.batteryID : String(format: "%06d", index) + idSuffix,
                title: name, primaryMetric: .networkDownloadBytesPerSecond,
                secondaryMetric: .networkUploadBytesPerSecond, ringMetric: .storageUsedPercent)
        }
        preferences.telemetryAlertRules = (0..<16).map {
            TelemetryAlertRule(id: String(format: "%06d", $0) + idSuffix, name: name)
        }
        preferences.selectedCapsuleID = preferences.capsuleProfiles[11].id
        let storage = try #require(StorageTelemetry(totalBytes: 1000, freeBytes: 100, availableBytes: 100,
            path: "/", fileSystem: "apfs"))
        let snapshot = TelemetrySnapshot(sampledAt: 100, battery: BatterySnapshot(hasBattery: true, percent: 68),
            power: PowerTelemetry(batteryWatts: -12, averageDischargeWatts: 10, adapterWatts: 60, cycleCount: 26),
            compute: ComputeTelemetry(cpuFraction: 0.25, memoryUsedBytes: 123456, memoryTotalBytes: 987654,
                compressedBytes: 1234, swapUsedBytes: 123, pressure: .normal), thermal: .fair,
            network: NetworkTelemetry(downloadBytesPerSecond: 123, uploadBytesPerSecond: 456,
                receivedBytes: UInt64.max, sentBytes: UInt64.max, interfaces: ["en0", "en1"]),
            storage: storage)
        let message = SettingsMessage(.telemetry, preferences: preferences, revision: Int.max,
            shortcutMessage: "Shortcut registered", tab: 6, frame: "{{100,200},{620,520}}",
            displayID: UInt32.max, telemetry: snapshot, visible: true, profileID: preferences.selectedCapsuleID)
        let encoded = try JSONEncoder().encode(message)
        #expect(name.utf8.count == 1024 && preferences.telemetryAlertRules[0].id.utf8.count == 256)
        #expect(SettingsMessage.maximumPayloadBytes == 131_072)
        #expect(encoded.count <= SettingsMessage.maximumPayloadBytes)
        let decoded = try JSONDecoder().decode(SettingsMessage.self, from: encoded)
        #expect(decoded.preferences == preferences && decoded.telemetry == snapshot)
    }
}
