import Foundation
import Testing
@testable import ChargeCore

struct ConfigurationLimitsTests {
    private func fixture(profiles count: Int = 12, rules: Int = 16, conditions: Int = 4) -> Preferences {
        var value = Preferences()
        value.capsuleProfiles = (0..<count).map { i in
            var profile = CapsuleProfile(id: i == 0 ? CapsuleProfile.batteryID : "p\(i)", title: "PROFILE \(i)", primaryMetric: .cpuPercent)
            profile.colorConditions = Array(repeating: CapsuleColorCondition(metric: .cpuPercent, comparison: .above, threshold: 50, accent: .red), count: conditions)
            return profile
        }
        value.telemetryAlertRules = (0..<rules).map { TelemetryAlertRule(id: "r\($0)") }
        value.playback.profileIDs = value.capsuleProfiles.map(\.id)
        return value
    }

    @Test func strictRawCountsAcceptExactAndRejectEachOverflow() throws {
        let exact = try ConfigurationShare(preferences: fixture())
        #expect(try ConfigurationShare.decode(exact.encoded()) == exact)
        let original = try #require(JSONSerialization.jsonObject(with: exact.encoded()) as? [String: Any])
        for field in ["profiles", "rules", "conditions", "playback"] {
            var root = original
            switch field {
            case "profiles":
                var entries = root["profiles"] as! [[String: Any]]
                var extra = entries[0]; extra["id"] = "overflow"; entries.append(extra); root["profiles"] = entries
            case "rules":
                var entries = root["rules"] as! [[String: Any]]
                var extra = entries[0]; extra["id"] = "overflow"; entries.append(extra); root["rules"] = entries
            case "conditions":
                var entries = root["profiles"] as! [[String: Any]]
                var conditions = entries[0]["colorConditions"] as! [[String: Any]]
                conditions.append(conditions[0]); entries[0]["colorConditions"] = conditions; root["profiles"] = entries
            default:
                var playback = root["playback"] as! [String: Any]
                playback["profileIDs"] = (playback["profileIDs"] as! [String]) + ["overflow"]; root["playback"] = playback
            }
            let expected: ConfigurationShareError = field == "profiles" ? .profileLimit : field == "rules" ? .ruleLimit : .invalidField(field == "conditions" ? "profiles[0].colorConditions.count" : "playback.profileIDs.count")
            #expect(throws: expected) { try ConfigurationShare.decode(JSONSerialization.data(withJSONObject: root)) }
        }
    }

    @Test func legacyDecodeBoundsCountsAndPreservesExactConfiguration() throws {
        let exact = fixture()
        #expect(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(exact)) == exact)
        var root = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(exact)) as? [String: Any])
        // Raw JSON avoids the forgiving encoder normalizing away overflow before decode.
        let overflowing = fixture(profiles: 13, rules: 17, conditions: 5)
        root["capsuleProfiles"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(overflowing.capsuleProfiles))
        root["telemetryAlertRules"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(overflowing.telemetryAlertRules))
        root["playback"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(overflowing.playback))
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: root))
        #expect(decoded.capsuleProfiles.count == 12)
        #expect(decoded.telemetryAlertRules.count == 16)
        #expect(decoded.capsuleProfiles.allSatisfy { $0.colorConditions.count == 4 })
        #expect(decoded.playback.profileIDs == exact.playback.profileIDs)
    }

    @Test func requiredBatteryInsertionRejectsStrictOverflowButLegacyDropsLastAndPrunesReferences() throws {
        var value = fixture()
        value.capsuleProfiles[0].id = "custom"
        value.selectedCapsuleID = "p11"
        value.playback.profileIDs = ["missing", "p11", "custom", "p10"]
        let share = try ConfigurationShare(preferences: value)
        #expect(throws: ConfigurationShareError.profileLimit) { try share.preview(mode: .replace, local: Preferences()) }
        value.playback.profileIDs.insert("p11", at: 2)
        value.normalizeTelemetryConfiguration()
        #expect(value.capsuleProfiles.count == 12)
        #expect(value.capsuleProfiles.first?.id == CapsuleProfile.batteryID)
        #expect(value.capsuleProfiles.last?.id == "p10")
        #expect(value.selectedCapsuleID == CapsuleProfile.batteryID)
        #expect(value.playback.profileIDs == ["custom", "p10"])
        var fitting = share; fitting.profiles.removeLast()
        let imported = try fitting.preview(mode: .replace, local: Preferences())
        #expect(imported.preferences.capsuleProfiles.count == 12)
        #expect(imported.preferences.playback.profileIDs == ["custom", "p10"])
    }
}
