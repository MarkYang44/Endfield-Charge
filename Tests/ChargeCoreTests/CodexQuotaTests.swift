import Foundation
import Testing
@testable import ChargeCore

struct CodexQuotaTests {
    @Test func testCodexBucketAndDurationSelectRemainingRatherThanPosition() throws {
        let data = Data(#"{"rateLimitsByLimitId":{"other":{"primary":{"usedPercent":1,"windowDurationMins":300}},"codex":{"primary":{"usedPercent":125,"windowDurationMins":10080,"resetsAt":2000},"secondary":{"usedPercent":-5,"windowDurationMins":300,"resetsAt":1000}}}}"#.utf8)
        let quota = try CodexQuotaSnapshot.parse(data)
        #expect(quota.fiveHour?.remainingPercent == 100)
        #expect(quota.weekly?.remainingPercent == 0)
        #expect(quota.fiveHour?.resetsAt == 1000)
    }
    @Test func testUnknownAndLegacyBuckets() throws {
        #expect(try CodexQuotaSnapshot.parse(Data(#"{"rateLimitsByLimitId":{"other":{"primary":{"usedPercent":1,"windowDurationMins":300}}}}"#.utf8)).fiveHour == nil)
        #expect(try CodexQuotaSnapshot.parse(Data(#"{"rateLimits":{"limitId":"other","primary":{"usedPercent":1,"windowDurationMins":300}}}"#.utf8)).fiveHour == nil)
        #expect(try CodexQuotaSnapshot.parse(Data(#"{"rateLimits":{"limitId":"codex","primary":{"usedPercent":23,"windowDurationMins":300},"secondary":{"windowDurationMins":10080}}}"#.utf8)).fiveHour?.remainingPercent == 77)
        #expect(CodexQuotaWindow(usedPercent: .infinity, resetsAt: 0) == nil)
    }
    @Test func testOldSnapshotAndNewMetricRoundTrip() throws {
        var snapshot = TelemetrySnapshot(sampledAt: 1, battery: BatterySnapshot(hasBattery: false), power: nil, compute: nil, thermal: nil)
        let old = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(TelemetrySnapshot.self, from: old).codexQuota == nil)
        snapshot.codexQuota = CodexQuotaSnapshot(fiveHour: CodexQuotaWindow(usedPercent: 12, resetsAt: 3000), weekly: nil)
        #expect(TelemetryMetric.codexFiveHourRemainingPercent.value(in: snapshot) == 88)
        #expect(TelemetryMetric.codexWeeklyRemainingPercent.value(in: snapshot) == nil)
        #expect(try JSONDecoder().decode(TelemetrySnapshot.self, from: JSONEncoder().encode(snapshot)) == snapshot)
        #expect(CapsuleProfile.defaults.count == 5)
    }
    @Test func testCountdownUsesInjectedUnixTime() {
        #expect(CodexQuotaCountdown.text(resetsAt: nil, at: 0, chinese: false) == "—")
        #expect(CodexQuotaCountdown.text(resetsAt: 59, at: 0, chinese: false) == "<1m")
        #expect(CodexQuotaCountdown.text(resetsAt: 90061, at: 0, chinese: false) == "1d 1h")
        #expect(CodexQuotaCountdown.text(resetsAt: 3661, at: 0, chinese: true) == "1时 1分")
        #expect(CodexQuotaCountdown.text(resetsAt: 1, at: 2, chinese: false) == "Reset due")
    }
}
