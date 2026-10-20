import Foundation
import Testing
@testable import ChargeCore

struct CapsulePresentationConfigurationTests {
    private func snapshot(_ thermal: ThermalLevel? = nil, pressure: MemoryPressureLevel? = nil,
                          cpu: Double? = nil) -> TelemetrySnapshot {
        TelemetrySnapshot(sampledAt: 0, battery: BatterySnapshot(percent: 50), power: nil,
            compute: pressure == nil && cpu == nil ? nil : ComputeTelemetry(cpuFraction: cpu,
                memoryUsedBytes: nil, memoryTotalBytes: 0, compressedBytes: nil, swapUsedBytes: nil,
                pressure: pressure ?? .unknown), thermal: thermal)
    }
    private func stateRule(target: TelemetryState? = nil, hold: Double = 0,
                           cooldown: Double = 10) -> TelemetryAlertRule {
        TelemetryAlertRule(id: "state", enabled: true, holdSeconds: hold, cooldownSeconds: cooldown,
            condition: .stateChange, source: .thermal, targetState: target)
    }

    @Test func oldJSONPreservesShortcutAndNewFeaturesDefaultOff() throws {
        let data = Data(#"{"shortcutKey":"E","shortcutModifiers":["command","shift"],"telemetryAlertRules":[{"id":"old","enabled":true,"metric":"cpuPercent","threshold":75}]}"#.utf8)
        let value = try JSONDecoder().decode(Preferences.self, from: data)
        #expect(value.shortcutKey == "E" && value.shortcutModifiers == [.command, .shift])
        #expect(value.playback == CapsulePlayback())
        #expect(!value.playback.persistent && !value.playback.rotationEnabled)
        #expect(value.playback.profileIDs.isEmpty && value.playback.intervalSeconds == 15)
        #expect(value.capsuleProfiles.allSatisfy { $0.colorConditions.isEmpty })
        #expect(value.telemetryAlertRules[0].condition == .threshold)
        #expect(value.telemetryAlertRules[0].source == nil && value.telemetryAlertRules[0].targetState == nil)
    }

    @Test func firstMatchingColorWinsAndMissingMetricSkips() {
        var profile = CapsuleProfile.defaults[1]
        profile.colorConditions = [
            CapsuleColorCondition(metric: .networkDownloadBytesPerSecond, comparison: .above, threshold: 0, accent: .red),
            CapsuleColorCondition(metric: .cpuPercent, comparison: .above, threshold: 40, accent: .amber),
            CapsuleColorCondition(metric: .cpuPercent, comparison: .above, threshold: 50, accent: .red)]
        #expect(profile.resolvedAccent(in: snapshot(cpu: 0.75)) == .amber)
        #expect(profile.resolvedAccent(in: snapshot(cpu: 0.4)) == .theme)
        #expect(profile.resolvedAccent(in: snapshot()) == .theme)
        profile.colorConditions[1].accent = .theme
        #expect(profile.resolvedAccent(in: snapshot(cpu: 0.75)) == .theme)
    }

    @Test func colorsAreBoundedFiniteAndUseStrictComparisons() throws {
        var profile = CapsuleProfile.defaults[1]
        profile.colorConditions = [CapsuleColorCondition(metric: .cpuPercent, comparison: .below, threshold: 50, accent: .lime)]
        #expect(profile.resolvedAccent(in: snapshot(cpu: 0.5)) == .theme)
        #expect(profile.resolvedAccent(in: snapshot(cpu: 0.49)) == .lime)
        profile.colorConditions[0].threshold = .nan
        #expect(profile.resolvedAccent(in: snapshot(cpu: 0.49)) == .theme)
        profile.colorConditions = Array(repeating: CapsuleColorCondition(metric: .cpuPercent, comparison: .above, threshold: 50, accent: .amber), count: 8)
        profile.normalize()
        #expect(profile.colorConditions.count == 4)
        #expect(try JSONDecoder().decode(CapsuleProfile.self, from: JSONEncoder().encode(profile)) == profile)
    }

    @Test func paletteOnlyBatteryRetainsDedicatedLayout() {
        var battery = CapsuleProfile.defaults[0]
        #expect(battery.isDefaultBattery && battery.isBatteryLayout)
        battery.colorConditions = [CapsuleColorCondition(metric: .batteryPercent, comparison: .below, threshold: 20, accent: .red)]
        #expect(!battery.isDefaultBattery && battery.isBatteryLayout)
        battery.title = "CUSTOM"
        #expect(!battery.isBatteryLayout)
        var custom = CapsuleProfile.defaults[0]; custom.id = "custom"
        #expect(!custom.isBatteryLayout)
    }

    @Test func stateValuesAreTypedKnownAndSourceCompatible() throws {
        #expect(TelemetryStateSource.thermal.value(in: snapshot(.serious)) == .thermal(.serious))
        #expect(TelemetryStateSource.memoryPressure.value(in: snapshot(pressure: .warning)) == .memoryPressure(.warning))
        #expect(TelemetryStateSource.thermal.value(in: snapshot(.unknown)) == nil)
        #expect(TelemetryStateSource.memoryPressure.value(in: snapshot(pressure: .unknown)) == nil)
        #expect(TelemetryStateSource.thermal.accepts(.thermal(.critical)))
        #expect(!TelemetryStateSource.thermal.accepts(.memoryPressure(.critical)))
        #expect(!TelemetryStateSource.thermal.accepts(.thermal(.unknown)))
        var rule = stateRule(target: .memoryPressure(.warning))
        #expect(rule.targetState == nil)
        rule.targetState = .thermal(.serious)
        #expect(try JSONDecoder().decode(TelemetryAlertRule.self, from: JSONEncoder().encode(rule)) == rule)
    }

    @Test func firstStateIsQuietAndEachObservedChangeFiresOnce() {
        var evaluator = TelemetryRuleEvaluator()
        let rule = stateRule()
        #expect(evaluator.evaluate(rules: [rule], snapshot: snapshot(.nominal), at: 0).isEmpty)
        #expect(evaluator.evaluate(rules: [rule], snapshot: snapshot(.serious), at: 1) == [rule.id])
        #expect(evaluator.evaluate(rules: [rule], snapshot: snapshot(.serious), at: 15).isEmpty)
        #expect(evaluator.evaluate(rules: [rule], snapshot: snapshot(.nominal), at: 16) == [rule.id])
    }

    @Test func stateTargetAndHoldCancelOnAnotherTransition() {
        var evaluator = TelemetryRuleEvaluator()
        let rule = stateRule(target: .thermal(.serious), hold: 5)
        _ = evaluator.evaluate(rules: [rule], snapshot: snapshot(.nominal), at: 0)
        #expect(evaluator.evaluate(rules: [rule], snapshot: snapshot(.serious), at: 1).isEmpty)
        #expect(evaluator.evaluate(rules: [rule], snapshot: snapshot(.critical), at: 3).isEmpty)
        #expect(evaluator.evaluate(rules: [rule], snapshot: snapshot(.critical), at: 8).isEmpty)
        #expect(evaluator.evaluate(rules: [rule], snapshot: snapshot(.serious), at: 9).isEmpty)
        #expect(evaluator.evaluate(rules: [rule], snapshot: snapshot(.serious), at: 13).isEmpty)
        #expect(evaluator.evaluate(rules: [rule], snapshot: snapshot(.serious), at: 14) == [rule.id])
    }

    @Test func anyChangeHoldRestartsWhenStateChangesAgain() {
        var evaluator = TelemetryRuleEvaluator()
        let rule = stateRule(hold: 5)
        _ = evaluator.evaluate(rules: [rule], snapshot: snapshot(.nominal), at: 0)
        _ = evaluator.evaluate(rules: [rule], snapshot: snapshot(.serious), at: 1)
        #expect(evaluator.evaluate(rules: [rule], snapshot: snapshot(.critical), at: 4).isEmpty)
        #expect(evaluator.evaluate(rules: [rule], snapshot: snapshot(.critical), at: 6).isEmpty)
        #expect(evaluator.evaluate(rules: [rule], snapshot: snapshot(.critical), at: 9) == [rule.id])
    }

    @Test func cooldownSuppressedTransitionsNeverReplay() {
        var evaluator = TelemetryRuleEvaluator()
        let rule = stateRule(hold: 2, cooldown: 10)
        _ = evaluator.evaluate(rules: [rule], snapshot: snapshot(.nominal), at: 0)
        _ = evaluator.evaluate(rules: [rule], snapshot: snapshot(.serious), at: 1)
        #expect(evaluator.evaluate(rules: [rule], snapshot: snapshot(.serious), at: 3) == [rule.id])
        _ = evaluator.evaluate(rules: [rule], snapshot: snapshot(.critical), at: 12)
        #expect(evaluator.evaluate(rules: [rule], snapshot: snapshot(.critical), at: 14).isEmpty)
        #expect(evaluator.evaluate(rules: [rule], snapshot: snapshot(.critical), at: 20).isEmpty)
        _ = evaluator.evaluate(rules: [rule], snapshot: snapshot(.fair), at: 21)
        #expect(evaluator.evaluate(rules: [rule], snapshot: snapshot(.fair), at: 23) == [rule.id])
    }

    @Test func unknownAndLongGapResetBaselineWithoutEvadingCooldown() {
        var evaluator = TelemetryRuleEvaluator()
        let rule = stateRule(cooldown: 200)
        _ = evaluator.evaluate(rules: [rule], snapshot: snapshot(.nominal), at: 0)
        #expect(evaluator.evaluate(rules: [rule], snapshot: snapshot(.serious), at: 1) == [rule.id])
        _ = evaluator.evaluate(rules: [rule], snapshot: snapshot(.unknown), at: 2)
        #expect(evaluator.evaluate(rules: [rule], snapshot: snapshot(.nominal), at: 3).isEmpty)
        #expect(evaluator.evaluate(rules: [rule], snapshot: snapshot(.critical), at: 4).isEmpty)
        #expect(evaluator.evaluate(rules: [rule], snapshot: snapshot(.nominal), at: 70).isEmpty)
        #expect(evaluator.evaluate(rules: [rule], snapshot: snapshot(.serious), at: 71).isEmpty)
        _ = evaluator.evaluate(rules: [rule], snapshot: snapshot(.serious), at: 120)
        _ = evaluator.evaluate(rules: [rule], snapshot: snapshot(.serious), at: 170)
        #expect(evaluator.evaluate(rules: [rule], snapshot: snapshot(.serious), at: 201).isEmpty)
        #expect(evaluator.evaluate(rules: [rule], snapshot: snapshot(.nominal), at: 202) == [rule.id])
    }

    @Test func unknownCancelsHoldAndFirstKnownOnlySetsBaseline() {
        var evaluator = TelemetryRuleEvaluator()
        let rule = stateRule(hold: 2)
        _ = evaluator.evaluate(rules: [rule], snapshot: snapshot(.nominal), at: 0)
        _ = evaluator.evaluate(rules: [rule], snapshot: snapshot(.serious), at: 1)
        _ = evaluator.evaluate(rules: [rule], snapshot: snapshot(), at: 2)
        #expect(evaluator.evaluate(rules: [rule], snapshot: snapshot(.serious), at: 3).isEmpty)
        #expect(evaluator.evaluate(rules: [rule], snapshot: snapshot(.serious), at: 10).isEmpty)
        _ = evaluator.evaluate(rules: [rule], snapshot: snapshot(.critical), at: 11)
        #expect(evaluator.evaluate(rules: [rule], snapshot: snapshot(.critical), at: 13) == [rule.id])
    }

    @Test func editedDisabledAndResetRulesNeedFreshBaseline() {
        var evaluator = TelemetryRuleEvaluator()
        var rule = stateRule()
        _ = evaluator.evaluate(rules: [rule], snapshot: snapshot(.nominal), at: 0)
        rule.name = "CHANGED"
        #expect(evaluator.evaluate(rules: [rule], snapshot: snapshot(.serious), at: 1).isEmpty)
        rule.enabled = false
        _ = evaluator.evaluate(rules: [rule], snapshot: snapshot(.nominal), at: 2)
        rule.enabled = true
        #expect(evaluator.evaluate(rules: [rule], snapshot: snapshot(.critical), at: 3).isEmpty)
        evaluator.reset()
        #expect(evaluator.evaluate(rules: [rule], snapshot: snapshot(.nominal), at: 4).isEmpty)
    }

    @Test func memoryPressureRulesAndThresholdRulesKeepConfigurationOrder() {
        var evaluator = TelemetryRuleEvaluator()
        let threshold = TelemetryAlertRule(id: "threshold", enabled: true, threshold: 50)
        var memory = stateRule(target: .memoryPressure(.warning)); memory.source = .memoryPressure
        memory.targetState = .memoryPressure(.warning)
        _ = evaluator.evaluate(rules: [memory, threshold], snapshot: snapshot(pressure: .normal, cpu: 0.1), at: 0)
        #expect(evaluator.evaluate(rules: [memory, threshold], snapshot: snapshot(pressure: .warning, cpu: 0.9), at: 1) == [memory.id, threshold.id])
        #expect(evaluator.evaluate(rules: [memory, threshold], values: [.cpuPercent: 10], at: 2).isEmpty)
        #expect(evaluator.evaluate(rules: [memory, threshold], snapshot: snapshot(pressure: .critical, cpu: 0.1), at: 3).isEmpty)
    }

    @Test func thresholdCooldownStillWaitsWithinSameExcursion() {
        var evaluator = TelemetryRuleEvaluator()
        let rule = TelemetryAlertRule(id: "threshold", enabled: true, threshold: 50, cooldownSeconds: 10)
        _ = evaluator.evaluate(rules: [rule], values: [.cpuPercent: 50], at: 0)
        #expect(evaluator.evaluate(rules: [rule], values: [.cpuPercent: 51], at: 1) == [rule.id])
        _ = evaluator.evaluate(rules: [rule], values: [.cpuPercent: 50], at: 2)
        #expect(evaluator.evaluate(rules: [rule], values: [.cpuPercent: 51], at: 3).isEmpty)
        #expect(evaluator.evaluate(rules: [rule], values: [.cpuPercent: 51], at: 11) == [rule.id])
    }

    @Test func playbackNormalizesReferencesOrderAndInterval() throws {
        let profiles = CapsuleProfile.defaults
        var value = CapsulePlayback(persistent: true, rotationEnabled: true,
            profileIDs: ["missing", profiles[2].id, profiles[1].id, profiles[2].id], intervalSeconds: 1)
        value.normalize(profiles: profiles)
        #expect(value.profileIDs == [profiles[2].id, profiles[1].id])
        #expect(value.rotationEnabled && value.persistent && value.intervalSeconds == 10)
        #expect(value.effectiveProfileIDs(selectedID: profiles[0].id, profiles: profiles) == value.profileIDs)
        value.intervalSeconds = 999; value.normalize(profiles: profiles)
        #expect(value.intervalSeconds == 600)
        value.intervalSeconds = .nan; value.normalize(profiles: profiles)
        #expect(value.intervalSeconds == 15)
        #expect(try JSONDecoder().decode(CapsulePlayback.self, from: JSONEncoder().encode(value)) == value)
    }

    @Test func playbackOneItemEmptyAndDisabledFallback() {
        let profiles = CapsuleProfile.defaults
        var value = CapsulePlayback(rotationEnabled: true, profileIDs: [profiles[1].id])
        value.normalize(profiles: profiles)
        #expect(value.effectiveProfileIDs(selectedID: profiles[0].id, profiles: profiles) == [profiles[1].id])
        value.profileIDs = ["deleted"]; value.normalize(profiles: profiles)
        #expect(value.profileIDs.isEmpty && !value.rotationEnabled)
        #expect(value.effectiveProfileIDs(selectedID: profiles[2].id, profiles: profiles) == [profiles[2].id])
        #expect(value.effectiveProfileIDs(selectedID: "deleted", profiles: profiles) == [CapsuleProfile.batteryID])
        value.profileIDs = [profiles[1].id]
        #expect(value.effectiveProfileIDs(selectedID: profiles[0].id, profiles: profiles) == [profiles[0].id])
    }

    @Test func preferencesNormalizePlaybackAfterRemovingInvalidProfiles() throws {
        var value = Preferences()
        value.playback = CapsulePlayback(persistent: true, rotationEnabled: true,
            profileIDs: ["deleted", CapsuleProfile.cpuID, CapsuleProfile.cpuID], intervalSeconds: 17)
        value.normalizeTelemetryConfiguration()
        #expect(value.playback.profileIDs == [CapsuleProfile.cpuID])
        #expect(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(value)) == value)
    }
}
