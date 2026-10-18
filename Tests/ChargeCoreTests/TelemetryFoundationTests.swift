import Foundation
import Testing
@testable import ChargeCore

struct TelemetryFoundationTests {
    private func counter(_ name: String, _ received: UInt64, _ sent: UInt64, index: UInt32 = 1) -> NetworkInterfaceCounter {
        NetworkInterfaceCounter(name: name, index: index, receivedBytes: received, sentBytes: sent)
    }
    @Test func networkBaselineAnd64BitDeltas() throws {
        var sampler = NetworkRateSampler()
        let base = UInt64(UInt32.max) + 100
        let firstSample = sampler.sample([counter("en0", base, base)], at: 1)
        let first = try #require(firstSample)
        #expect(first.downloadBytesPerSecond == nil && first.receivedBytes == 0)
        let secondSample = sampler.sample([counter("en0", base + 400, base + 100)], at: 3)
        let second = try #require(secondSample)
        #expect(second.downloadBytesPerSecond == 200 && second.uploadBytesPerSecond == 50)
        #expect(second.receivedBytes == 400 && second.sentBytes == 100 && second.interfaceCount == 1)
    }
    @Test func changedInterfacesDoNotHideValidRemainingDelta() throws {
        var sampler = NetworkRateSampler()
        _ = sampler.sample([counter("en0", 100, 100), counter("en1", 1000, 1000, index: 2)], at: 1)
        let readingSample = sampler.sample([counter("en0", 150, 120), counter("en1", 2, 2, index: 2), counter("en2", 9_000_000, 9_000_000, index: 3)], at: 2)
        let reading = try #require(readingSample)
        #expect(reading.downloadBytesPerSecond == 50 && reading.receivedBytes == 50)
        #expect(reading.interfaces == ["en0", "en1", "en2"])
        let resetSample = sampler.sample([counter("en3", 500, 600, index: 4)], at: 3)
        let reset = try #require(resetSample)
        #expect(reset.downloadBytesPerSecond == nil && reset.receivedBytes == 50)
    }
    @Test func unavailableLongGapAndClockResetNeverInventTraffic() throws {
        var sampler = NetworkRateSampler()
        _ = sampler.sample([counter("en0", 1, 1)], at: 1)
        #expect(sampler.sample(nil, at: 2) == nil)
        #expect(sampler.sample([counter("en0", 1000, 1000)], at: 3)?.downloadBytesPerSecond == nil)
        #expect(sampler.sample([counter("en0", 9000, 9000)], at: 100)?.receivedBytes == 0)
        #expect(sampler.sample([counter("en0", 9500, 9500)], at: 99)?.downloadBytesPerSecond == nil)
        #expect(sampler.sample([counter("en0", 9600, 9600)], at: 100)?.downloadBytesPerSecond == 100)
        sampler.reset()
        #expect(sampler.sample([counter("en0", 9700, 9700)], at: 101)?.receivedBytes == 0)
    }
    @Test func sessionTotalsSaturateInsteadOfOverflowing() {
        var sampler = NetworkRateSampler()
        _ = sampler.sample([counter("en0", 0, 0), counter("en1", 0, 0, index: 2)], at: 1)
        let value = sampler.sample([counter("en0", .max, .max), counter("en1", .max, .max, index: 2)], at: 2)
        #expect(value?.receivedBytes == UInt64.max)
        #expect(value?.downloadBytesPerSecond?.isFinite == true)
    }
    @Test func storageDistinguishesFreeAndAvailable() throws {
        let value = try #require(StorageTelemetry(totalBytes: 1000, freeBytes: 400, availableBytes: 300, path: "/", fileSystem: "apfs"))
        #expect(value.usedFraction == 0.6 && value.availableBytes == 300 && value.freeBytes == 400)
        #expect(StorageTelemetry(totalBytes: 0, freeBytes: 0, availableBytes: 0, path: "/", fileSystem: "apfs") == nil)
        #expect(StorageTelemetry(totalBytes: 10, freeBytes: 20, availableBytes: 1, path: "/", fileSystem: "apfs") == nil)
    }
    @Test func oldSnapshotAndPreferencesDecodeWithoutNewFields() throws {
        let snapshot = TelemetrySnapshot(sampledAt: 1, battery: BatterySnapshot(), power: nil, compute: nil, thermal: nil)
        let old = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(TelemetrySnapshot.self, from: old)
        #expect(decoded.network == nil && decoded.storage == nil)
        let preferences = try JSONDecoder().decode(Preferences.self, from: Data(#"{"shortcutKey":"E","shortcutModifiers":["command","shift"]}"#.utf8))
        #expect(preferences.networkTelemetryEnabled && preferences.storageTelemetryEnabled)
        #expect(preferences.selectedCapsuleID == CapsuleProfile.batteryID)
        #expect(preferences.telemetryAlertRules.isEmpty && preferences.capsuleProfiles.count == 5)
        #expect(preferences.shortcutKey == "E" && preferences.shortcutModifiers == [.command, .shift])
        #expect(Preferences() == Preferences())
    }
    @Test func invalidProfilesAndRulesAreBoundedAndNormalized() throws {
        var preferences = Preferences()
        let profile = CapsuleProfile(id: "custom", title: String(repeating: "x", count: 100), primaryMetric: .cpuPercent, ringMetric: .cpuPercent, referenceMaximum: .nan)
        preferences.capsuleProfiles = Array(repeating: profile, count: 50)
        preferences.selectedCapsuleID = "missing"
        let rule = TelemetryAlertRule(id: "rule", name: String(repeating: "y", count: 100), threshold: .infinity, holdSeconds: 999, cooldownSeconds: -1)
        preferences.telemetryAlertRules = Array(repeating: rule, count: 50)
        preferences.normalizeTelemetryConfiguration()
        #expect(preferences.capsuleProfiles.count <= 12 && preferences.capsuleProfiles.contains { $0.id == CapsuleProfile.batteryID })
        #expect(preferences.capsuleProfiles.allSatisfy { $0.title.count <= 32 && $0.referenceMaximum.isFinite && $0.referenceMaximum > 0 })
        #expect(preferences.capsuleProfiles.contains { $0.id == preferences.selectedCapsuleID })
        #expect(preferences.telemetryAlertRules.count <= 16)
        #expect(preferences.telemetryAlertRules.allSatisfy { $0.threshold.isFinite && $0.holdSeconds <= 300 && $0.cooldownSeconds >= 10 })
        #expect(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences)) == preferences)
    }
    @Test func persistedArraysSkipMalformedNeighborsAndRestoreBattery() throws {
        let json = #"{"networkTelemetryEnabled":false,"storageTelemetryEnabled":false,"selectedCapsuleID":"deleted","capsuleProfiles":[null,{"id":"valid","title":"NET","primaryMetric":"networkDownloadBytesPerSecond","referenceMaximum":0},{"id":"invalid","primaryMetric":"arbitrary.expression"}],"telemetryAlertRules":[null,{"id":"good","metric":"cpuPercent","threshold":42.5,"holdSeconds":1.5,"cooldownSeconds":12.5},{"id":"bad","metric":"shell"}]}"#
        let value = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        #expect(!value.networkTelemetryEnabled && !value.storageTelemetryEnabled)
        #expect(value.capsuleProfiles.map(\.id) == [CapsuleProfile.batteryID, "valid"])
        #expect(value.selectedCapsuleID == CapsuleProfile.batteryID)
        #expect(value.telemetryAlertRules.count == 1 && !value.telemetryAlertRules[0].enabled)
        #expect(value.telemetryAlertRules[0].threshold == 42.5 && value.telemetryAlertRules[0].holdSeconds == 1.5)
        #expect(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(value)) == value)
    }
    @Test func encodingNormalizesMutatedModelsAndBoundsPayload() throws {
        var value = Preferences()
        var profile = CapsuleProfile.custom()
        profile.referenceMaximum = .infinity; profile.title = String(repeating: "x", count: 100)
        value.capsuleProfiles = Array(repeating: profile, count: 100)
        var rule = TelemetryAlertRule.custom(); rule.threshold = .nan
        value.telemetryAlertRules = Array(repeating: rule, count: 100)
        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Preferences.self, from: encoded)
        #expect(decoded.capsuleProfiles.count <= 12 && decoded.telemetryAlertRules.count <= 16)
        #expect(decoded.capsuleProfiles.allSatisfy { $0.referenceMaximum.isFinite && $0.title.count <= 32 })
        #expect(decoded.telemetryAlertRules.allSatisfy { $0.threshold.isFinite })
    }
    @Test func snapshotRoundTripsNewModulesAndRejectsInvalidStorage() throws {
        let network = NetworkTelemetry(downloadBytesPerSecond: 12.5, uploadBytesPerSecond: 3.5, receivedBytes: 25, sentBytes: 7, interfaces: ["en0"])
        let storage = StorageTelemetry(totalBytes: 1000, freeBytes: 400, availableBytes: 300, path: "/", fileSystem: "apfs")
        let snapshot = TelemetrySnapshot(sampledAt: 1, battery: BatterySnapshot(), power: nil, compute: nil, thermal: nil, network: network, storage: storage)
        #expect(try JSONDecoder().decode(TelemetrySnapshot.self, from: JSONEncoder().encode(snapshot)) == snapshot)
        let invalid = Data(#"{"totalBytes":1,"freeBytes":2,"availableBytes":0,"path":"/","fileSystem":"apfs"}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(StorageTelemetry.self, from: invalid) }
    }
    @Test func emptyOrReindexedNetworkStaysUnknownRatherThanZero() {
        var sampler = NetworkRateSampler()
        _ = sampler.sample([counter("en0", 100, 100)], at: 1)
        let reindexed = sampler.sample([counter("en0", 500, 500, index: 2)], at: 2)
        #expect(reindexed?.downloadBytesPerSecond == nil && reindexed?.receivedBytes == 0)
        let empty = sampler.sample([], at: 3)
        #expect(empty?.interfaceCount == 0 && empty?.downloadBytesPerSecond == nil)
        #expect(sampler.sample([counter("en0", 900, 900, index: 2)], at: 4)?.downloadBytesPerSecond == nil)
        #expect(sampler.sample([counter("en0", 900, 900, index: 2)], at: 5)?.downloadBytesPerSecond == 0)
    }
    @Test func metricsPreserveMissingAndUsePercentUnits() throws {
        let snapshot = TelemetrySnapshot(sampledAt: 1, battery: BatterySnapshot(percent: 25, currentMAh: 1000, voltageMV: 10000), power: nil,
            compute: ComputeTelemetry(cpuFraction: 0.5, memoryUsedBytes: 250, memoryTotalBytes: 1000, compressedBytes: nil, swapUsedBytes: nil, pressure: .normal), thermal: nil)
        #expect(TelemetryMetric.cpuPercent.value(in: snapshot) == 50)
        #expect(TelemetryMetric.memoryPercent.value(in: snapshot) == 25)
        #expect(TelemetryMetric.batteryEnergyWh.value(in: snapshot) == 10)
        #expect(TelemetryMetric.networkDownloadBytesPerSecond.value(in: snapshot) == nil)
    }
}

struct TelemetryRuleFoundationTests {
    private let rule = TelemetryAlertRule(id: "cpu", name: "CPU", enabled: true, metric: .cpuPercent, threshold: 80, holdSeconds: 2, cooldownSeconds: 10)
    @Test func initiallyBadNeedsRecoveryThenCrossingAndHold() {
        var evaluator = TelemetryRuleEvaluator()
        #expect(evaluator.evaluate(rules: [rule], values: [.cpuPercent: 90], at: 0).isEmpty)
        #expect(evaluator.evaluate(rules: [rule], values: [.cpuPercent: 95], at: 4).isEmpty)
        _ = evaluator.evaluate(rules: [rule], values: [.cpuPercent: 70], at: 5)
        #expect(evaluator.evaluate(rules: [rule], values: [.cpuPercent: 90], at: 6).isEmpty)
        #expect(evaluator.evaluate(rules: [rule], values: [.cpuPercent: 90], at: 7).isEmpty)
        #expect(evaluator.evaluate(rules: [rule], values: [.cpuPercent: 90], at: 8) == ["cpu"])
        #expect(evaluator.evaluate(rules: [rule], values: [.cpuPercent: 90], at: 20).isEmpty)
    }
    @Test func cooldownAndOneEventPerExcursion() {
        var evaluator = TelemetryRuleEvaluator()
        var immediate = rule; immediate.holdSeconds = 0
        _ = evaluator.evaluate(rules: [immediate], values: [.cpuPercent: 10], at: 0)
        #expect(evaluator.evaluate(rules: [immediate], values: [.cpuPercent: 90], at: 1) == ["cpu"])
        _ = evaluator.evaluate(rules: [immediate], values: [.cpuPercent: 10], at: 2)
        #expect(evaluator.evaluate(rules: [immediate], values: [.cpuPercent: 90], at: 3).isEmpty)
        #expect(evaluator.evaluate(rules: [immediate], values: [.cpuPercent: 90], at: 11) == ["cpu"])
        #expect(evaluator.evaluate(rules: [immediate], values: [.cpuPercent: 90], at: 12).isEmpty)
    }
    @Test func missingChangedDisabledDeletedAndClockGapsResetPending() {
        var evaluator = TelemetryRuleEvaluator()
        _ = evaluator.evaluate(rules: [rule], values: [.cpuPercent: 10], at: 0)
        _ = evaluator.evaluate(rules: [rule], values: [.cpuPercent: 90], at: 1)
        _ = evaluator.evaluate(rules: [rule], values: [:], at: 2)
        #expect(evaluator.evaluate(rules: [rule], values: [.cpuPercent: 90], at: 4).isEmpty)
        _ = evaluator.evaluate(rules: [rule], values: [.cpuPercent: 10], at: 5)
        _ = evaluator.evaluate(rules: [rule], values: [.cpuPercent: 90], at: 6)
        #expect(evaluator.evaluate(rules: [rule], values: [.cpuPercent: 90], at: 100).isEmpty)
        #expect(evaluator.evaluate(rules: [rule], values: [.cpuPercent: 90], at: 99).isEmpty)
        var changed = rule; changed.threshold = 70
        #expect(evaluator.evaluate(rules: [changed], values: [.cpuPercent: 90], at: 101).isEmpty)
        changed.enabled = false
        _ = evaluator.evaluate(rules: [changed], values: [.cpuPercent: 10], at: 102)
        changed.enabled = true
        #expect(evaluator.evaluate(rules: [changed], values: [.cpuPercent: 90], at: 103).isEmpty)
        _ = evaluator.evaluate(rules: [], values: [:], at: 104)
        #expect(evaluator.evaluate(rules: [rule], values: [.cpuPercent: 90], at: 105).isEmpty)
        evaluator.reset()
        #expect(evaluator.evaluate(rules: [rule], values: [.cpuPercent: 90], at: 106).isEmpty)
    }
    @Test func missingDataKeepsCooldownWhileRequiringFreshBaseline() {
        var evaluator = TelemetryRuleEvaluator()
        var immediate = rule; immediate.holdSeconds = 0
        _ = evaluator.evaluate(rules: [immediate], values: [.cpuPercent: 10], at: 0)
        #expect(evaluator.evaluate(rules: [immediate], values: [.cpuPercent: 90], at: 1) == ["cpu"])
        _ = evaluator.evaluate(rules: [immediate], values: [:], at: 2)
        _ = evaluator.evaluate(rules: [immediate], values: [.cpuPercent: 10], at: 3)
        #expect(evaluator.evaluate(rules: [immediate], values: [.cpuPercent: 90], at: 4).isEmpty)
        #expect(evaluator.evaluate(rules: [immediate], values: [.cpuPercent: 90], at: 11) == ["cpu"])
    }
    @Test func snapshotEvaluationMapsTypedMetricsAndInvalidTimeResets() {
        var evaluator = TelemetryRuleEvaluator()
        let low = TelemetryAlertRule(id: "low", enabled: true, metric: .batteryPercent, comparison: .below, threshold: 20)
        let healthy = TelemetrySnapshot(sampledAt: 1, battery: BatterySnapshot(percent: 50), power: nil, compute: nil, thermal: nil)
        let depleted = TelemetrySnapshot(sampledAt: 2, battery: BatterySnapshot(percent: 10), power: nil, compute: nil, thermal: nil)
        #expect(evaluator.evaluate(rules: [low], snapshot: healthy, at: 1).isEmpty)
        #expect(evaluator.evaluate(rules: [low], snapshot: depleted, at: 2) == ["low"])
        #expect(evaluator.evaluate(rules: [low], snapshot: healthy, at: .nan).isEmpty)
        #expect(evaluator.evaluate(rules: [low], snapshot: depleted, at: 3).isEmpty)
    }
    @Test func belowComparisonTreatsEqualityAsRecovery() {
        var evaluator = TelemetryRuleEvaluator()
        let low = TelemetryAlertRule(id: "low", name: "LOW", enabled: true, metric: .batteryPercent, comparison: .below, threshold: 20)
        _ = evaluator.evaluate(rules: [low], values: [.batteryPercent: 20], at: 0)
        #expect(evaluator.evaluate(rules: [low], values: [.batteryPercent: 19], at: 1) == ["low"])
    }
}
