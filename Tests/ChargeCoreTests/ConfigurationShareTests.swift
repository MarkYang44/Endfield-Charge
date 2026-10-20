import Foundation
import Testing
@testable import ChargeCore

struct ConfigurationShareTests {
    func sample() throws -> ConfigurationShare { try ConfigurationShare(preferences: Preferences()) }
    func changedJSON(_ change: (inout [String: Any]) -> Void) throws -> Data {
        var json = try #require(JSONSerialization.jsonObject(with: sample().encoded()) as? [String: Any])
        change(&json)
        return try JSONSerialization.data(withJSONObject: json)
    }
    func rejects(_ change: (inout [String: Any]) -> Void) throws {
        let data = try changedJSON(change)
        #expect(throws: (any Error).self) { try ConfigurationShare.decode(data) }
    }

    @Test func actualJSONRoundtripExcludesMachinePreferences() throws {
        var local = Preferences(); local.shortcutKey = "E"; local.language = "zh"; local.displayID = 42
        let share = try ConfigurationShare(preferences: local)
        let bytes = try share.encoded()
        #expect(try ConfigurationShare.decode(bytes) == share)
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(!text.contains("shortcut") && !text.contains("displayID") && !text.contains("language"))
    }
    @Test func rejectsUnknownVersionAndEnums() throws {
        try rejects { $0["schemaVersion"] = 99 }
        try rejects { $0["format"] = "alien" }
        try rejects { root in var p = root["profiles"] as! [[String: Any]]; p[0]["primaryMetric"] = "alien"; root["profiles"] = p }
    }
    @Test func rejectsRawTextBeforeForgivingNormalization() throws {
        for bad in ["", " ", String(repeating: "a", count: 65), "e" + String(repeating: "\u{301}", count: 600)] {
            try rejects { root in var p = root["profiles"] as! [[String: Any]]; p[0]["id"] = bad; root["profiles"] = p }
        }
        try rejects { root in var p = root["profiles"] as! [[String: Any]]; p[0]["title"] = String(repeating: "x", count: 33); root["profiles"] = p }
        try rejects { root in var p = root["profiles"] as! [[String: Any]]; p[0].removeValue(forKey: "title"); root["profiles"] = p }
    }
    @Test func rejectsDuplicatesCountsMalformedConditionsAndPlayback() throws {
        try rejects { root in let p = root["profiles"] as! [[String: Any]]; root["profiles"] = [p[0], p[0]] }
        try rejects { root in let p = root["profiles"] as! [[String: Any]]; root["profiles"] = Array(repeating: p[0], count: 13) }
        try rejects { root in var p = root["profiles"] as! [[String: Any]]; p[0]["colorConditions"] = [["metric": "bad"]]; root["profiles"] = p }
        try rejects { root in var q = root["playback"] as! [String: Any]; q["profileIDs"] = ["a", "a"]; root["playback"] = q }
        try rejects { root in var q = root["playback"] as! [String: Any]; q["profileIDs"] = Array(repeating: "a", count: 13); root["playback"] = q }
        try rejects { root in var q = root["playback"] as! [String: Any]; q["intervalSeconds"] = 9; root["playback"] = q }
    }
    @Test func rejectsRawStateTargetMismatchAndRuleBounds() throws {
        var local = Preferences()
        local.telemetryAlertRules = [TelemetryAlertRule(id: "r", condition: .stateChange, source: .thermal, targetState: .thermal(.critical))]
        let bytes = try ConfigurationShare(preferences: local).encoded()
        var root = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var rules = root["rules"] as! [[String: Any]]
        rules[0]["source"] = "memoryPressure"; root["rules"] = rules
        #expect(throws: (any Error).self) { try ConfigurationShare.decode(JSONSerialization.data(withJSONObject: root)) }
        rules[0]["source"] = "thermal"; rules[0]["holdSeconds"] = 301; root["rules"] = rules
        #expect(throws: (any Error).self) { try ConfigurationShare.decode(JSONSerialization.data(withJSONObject: root)) }
        root["rules"] = Array(repeating: rules[0], count: 17)
        #expect(throws: (any Error).self) { try ConfigurationShare.decode(JSONSerialization.data(withJSONObject: root)) }
    }
    @Test func rejectsNonfiniteAndRawInvalidTypedValues() throws {
        var share = try sample(); share.profiles[0].referenceMaximum = .infinity
        #expect(throws: (any Error).self) { try share.encoded() }
        share = try sample(); share.profiles[0].colorConditions = [CapsuleColorCondition(metric: .cpuPercent, comparison: .above, threshold: .nan, accent: .red)]
        #expect(throws: (any Error).self) { try share.encoded() }
        share = try sample(); share.rules = [TelemetryAlertRule(id: "r")]; share.rules[0].threshold = .nan
        #expect(throws: (any Error).self) { try share.encoded() }
    }
    @Test func fileLimitCheckedBeforeParsing() throws {
        let bytes = try sample().encoded()
        var exact = bytes; exact.append(contentsOf: repeatElement(UInt8(32), count: ConfigurationShare.maximumFileBytes - bytes.count))
        #expect(try ConfigurationShare.decode(exact) == sample())
        exact.append(32)
        #expect(throws: ConfigurationShareError.fileTooLarge) { try ConfigurationShare.decode(exact) }
    }
    @Test func mergeMapsConflictAndPreservesLocalSwitchesShortcutAndRules() throws {
        var local = Preferences(); local.shortcutKey = "E"; local.playback.persistent = true; local.playback.rotationEnabled = true
        local.capsuleProfiles.append(CapsuleProfile(id: "same", title: "LOCAL", primaryMetric: .cpuPercent))
        local.playback.profileIDs = ["same"]
        local.telemetryAlertRules = [TelemetryAlertRule(id: "r", name: "LOCAL", enabled: true)]
        var source = Preferences(); source.capsuleProfiles.append(CapsuleProfile(id: "same", title: "IMPORTED", primaryMetric: .memoryPercent))
        source.playback = CapsulePlayback(persistent: true, rotationEnabled: true, profileIDs: ["same"], intervalSeconds: 42)
        source.telemetryAlertRules = [TelemetryAlertRule(id: "r", name: "IMPORTED", enabled: true)]
        let share = try ConfigurationShare(preferences: source)
        let result = try share.preview(mode: .merge, local: local)
        let mapped = try #require(result.profileIDMap["same"])
        #expect(mapped != "same" && result.preferences.capsuleProfiles.count == 7)
        #expect(result.preferences.capsuleProfiles.contains { $0.id == mapped && $0.title == "IMPORTED" })
        #expect(result.preferences.playback.profileIDs == ["same", mapped])
        #expect(result.preferences.playback.persistent && result.preferences.playback.rotationEnabled)
        #expect(result.preferences.playback.intervalSeconds == local.playback.intervalSeconds)
        #expect(result.preferences.shortcutKey == "E" && result.preferences.telemetryAlertRules[0].enabled)
        #expect(!result.preferences.telemetryAlertRules[1].enabled)
        #expect(try share.preview(mode: .merge, local: local) == result)
    }
    @Test func identicalMergeIsReusedAndModifiedBuiltinBecomesCustom() throws {
        let share = try sample(); let same = try share.preview(mode: .merge, local: Preferences())
        #expect(same.preferences == Preferences() && same.summary.addedProfiles == 0)
        var modified = share; modified.profiles[0].title = "MY BATTERY"
        let result = try modified.preview(mode: .replace, local: Preferences())
        #expect(result.preferences.capsuleProfiles.first { $0.id == CapsuleProfile.batteryID } == CapsuleProfile.defaults[0])
        let id = try #require(result.profileIDMap[CapsuleProfile.batteryID])
        #expect(id != CapsuleProfile.batteryID && result.preferences.selectedCapsuleID == id)
    }
    @Test func replaceOnlyShareScopeDisablesPlaybackAndRules() throws {
        var source = Preferences(); source.playback = CapsulePlayback(persistent: true, rotationEnabled: true, profileIDs: [CapsuleProfile.cpuID])
        source.telemetryAlertRules = [TelemetryAlertRule(id: "r", enabled: true)]
        var local = Preferences(); local.scale = 1.1; local.duration = 9; local.language = "zh"; local.displayID = 123; local.shortcutKey = "E"; local.networkTelemetryEnabled = false
        let result = try ConfigurationShare(preferences: source).preview(mode: .replace, local: local)
        var expected = local; expected.telemetryAlertRules = source.telemetryAlertRules; expected.telemetryAlertRules[0].enabled = false
        expected.playback.profileIDs = source.playback.profileIDs
        #expect(result.preferences == expected)
    }
    @Test func missingReferencesAreExplicitPreviewWarnings() throws {
        var share = try sample(); share.selectedProfileID = "missing"; share.playback.profileIDs = ["missing", CapsuleProfile.cpuID]
        let decoded = try ConfigurationShare.decode(share.encoded())
        let result = try decoded.preview(mode: .replace, local: Preferences())
        #expect(result.preferences.selectedCapsuleID == CapsuleProfile.batteryID)
        #expect(result.preferences.playback.profileIDs == [CapsuleProfile.cpuID])
        #expect(result.summary.discardedReferences == ["missing", "missing"])
    }
    @Test func overflowRejectsWithoutChangingLocal() throws {
        var local = Preferences()
        local.capsuleProfiles += (0..<7).map { CapsuleProfile(id: "local\($0)", title: "LOCAL", primaryMetric: .cpuPercent) }
        var share = try sample(); share.profiles.append(CapsuleProfile(id: "new", title: "NEW", primaryMetric: .cpuPercent))
        let unchanged = local
        #expect(throws: ConfigurationShareError.profileLimit) { try share.preview(mode: .merge, local: local) }
        #expect(local == unchanged)
        local.telemetryAlertRules = (0..<16).map { TelemetryAlertRule(id: "r\($0)") }
        share = try sample(); share.rules = [TelemetryAlertRule(id: "new", name: "NEW")]
        #expect(throws: ConfigurationShareError.ruleLimit) { try share.preview(mode: .merge, local: local) }
    }
    @Test func correlatedTransactionRequiresBothRevisionAndBaseline() throws {
        let local = Preferences()
        let request = try ConfigurationTransactionRequest(requestID: "request-1", expectedRevision: 3, baseline: local, action: .importShare(try sample(), mode: .merge))
        #expect(try request.matches(preferences: local, revision: 3))
        #expect(try !request.matches(preferences: local, revision: 4))
        var edited = local; edited.shortcutKey = "E"
        #expect(try !request.matches(preferences: edited, revision: 3))
        let message = SettingsMessage(.configurationRequest, transactionRequest: request)
        let data = try message.encodedBounded()
        #expect(try JSONDecoder().decode(SettingsMessage.self, from: data).transactionRequest == request)
    }
    @Test func maximumUnicodeShareAndActualRequestResultFitWire() throws {
        var local = Preferences()
        let name = "e" + String(repeating: "\u{301}", count: 511) + "x"
        let suffix = String(repeating: "👨‍👩‍👧‍👦", count: 10)
        local.capsuleProfiles = (0..<12).map { i in
            CapsuleProfile(id: i == 0 ? CapsuleProfile.batteryID : String(format: "%06d", i) + suffix, title: name,
                primaryMetric: .networkDownloadBytesPerSecond, secondaryMetric: .networkUploadBytesPerSecond,
                ringMetric: .storageUsedPercent, referenceMaximum: Double.greatestFiniteMagnitude,
                colorConditions: Array(repeating: CapsuleColorCondition(metric: .networkDownloadBytesPerSecond, comparison: .above, threshold: -Double.greatestFiniteMagnitude, accent: .amber), count: 4))
        }
        local.telemetryAlertRules = (0..<16).map { TelemetryAlertRule(id: String(format: "%06d", $0) + suffix, name: name, threshold: Double.greatestFiniteMagnitude, holdSeconds: 300, cooldownSeconds: 86400, condition: .stateChange, source: .memoryPressure, targetState: .memoryPressure(.critical)) }
        local.selectedCapsuleID = local.capsuleProfiles[11].id
        local.playback = CapsulePlayback(persistent: true, rotationEnabled: true, profileIDs: local.capsuleProfiles.map(\.id), intervalSeconds: 600)
        let share = try ConfigurationShare(preferences: local)
        #expect(try share.encoded().count <= ConfigurationShare.maximumFileBytes)
        #expect(try ConfigurationShare.decode(share.encoded()) == share)
        let request = try ConfigurationTransactionRequest(requestID: String(repeating: "r", count: 64), expectedRevision: Int.max, baseline: local, action: .importShare(share, mode: .replace))
        #expect(try SettingsMessage(.configurationRequest, preferences: local, revision: Int.max, transactionRequest: request).encodedBounded().count <= SettingsMessage.maximumPayloadBytes)
        let result = ConfigurationTransactionResult(requestID: request.requestID, status: .applied)
        #expect(try SettingsMessage(.configurationResult, preferences: local, revision: Int.max, transactionResult: result).encodedBounded().count <= SettingsMessage.maximumPayloadBytes)
    }
    @Test func canonicalBaselineSortsModifiersAndRejectsForgivingBackupDecode() throws {
        var local = Preferences(); local.shortcutModifiers = [.shift, .command, .option]
        let canonical = try ConfigurationTransactionRequest.canonicalPreferences(local)
        #expect(try ConfigurationTransactionRequest.validatedPreferences(canonical) == local)
        var json = try #require(JSONSerialization.jsonObject(with: canonical) as? [String: Any])
        json["shortcutModifiers"] = ["shift", "option", "command"]
        let reordered = try JSONSerialization.data(withJSONObject: json)
        #expect(try ConfigurationTransactionRequest.validatedPreferences(reordered) == local)
        let root = try #require(JSONSerialization.jsonObject(with: canonical) as? [String: Any])
        #expect(root["shortcutModifiers"] as? [String] == ["command", "option", "shift"])
        json["capsuleProfiles"] = [["id": "", "primaryMetric": "cpuPercent"]]
        #expect(throws: (any Error).self) { try ConfigurationTransactionRequest.validatedPreferences(JSONSerialization.data(withJSONObject: json)) }
        #expect(throws: (any Error).self) { try ConfigurationTransactionRequest.validatedPreferences(Data("{}".utf8)) }
    }
    @Test func rejectsUnknownRawStateEnumAndFifthCondition() throws {
        try rejects { root in var profiles = root["profiles"] as! [[String: Any]]
            profiles[0]["colorConditions"] = Array(repeating: ["metric": "cpuPercent", "comparison": "above", "threshold": 1, "accent": "red"] as [String: Any], count: 5)
            root["profiles"] = profiles
        }
        var share = try sample(); share.rules = [TelemetryAlertRule(id: "r", condition: .stateChange, source: .thermal)]
        var root = try #require(JSONSerialization.jsonObject(with: share.encoded()) as? [String: Any])
        var rules = root["rules"] as! [[String: Any]]; rules[0]["targetState"] = ["thermal": ["_0": "future"]]; root["rules"] = rules
        #expect(throws: (any Error).self) { try ConfigurationShare.decode(JSONSerialization.data(withJSONObject: root)) }
    }

    @Test func mergingSameModifiedBuiltinAndDisabledImportAgainReusesCopies() throws {
        var share = try sample(); share.profiles[0].title = "CUSTOM BATTERY"
        share.rules = [TelemetryAlertRule(id: "r", enabled: true)]
        let first = try share.preview(mode: .merge, local: Preferences())
        let second = try share.preview(mode: .merge, local: first.preferences)
        #expect(second.preferences == first.preferences)
        #expect(second.summary.addedProfiles == 0 && second.summary.addedRules == 0)
    }

}
