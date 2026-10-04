import Foundation
import Testing
@testable import ChargeCore

@Test func cpuUsesTickDifferencesAndRebaselinesAfterReset() {
    var sampler = CPUTickSampler()
    #expect(sampler.sample(CPUTicks(user: 10, system: 10, idle: 80, nice: 0)) == nil)
    #expect(sampler.sample(CPUTicks(user: 20, system: 20, idle: 160, nice: 0)) == 0.2)
    #expect(sampler.sample(CPUTicks(user: 1, system: 1, idle: 8, nice: 0)) == nil)
    #expect(sampler.sample(CPUTicks(user: 2, system: 2, idle: 16, nice: 0)) == 0.2)
    #expect(sampler.sample(CPUTicks(user: 2, system: 2, idle: 16, nice: 0)) == nil)
    sampler.reset()
    #expect(sampler.sample(CPUTicks(user: 20, system: 20, idle: 160, nice: 0)) == nil)
}

@Test func cpuNiceTicksCountAsBusyAndPartialResetIsUnknown() {
    var sampler = CPUTickSampler()
    _ = sampler.sample(CPUTicks(user: 10, system: 10, idle: 10, nice: 10))
    #expect(sampler.sample(CPUTicks(user: 10, system: 10, idle: 20, nice: 20)) == 0.5)
    #expect(sampler.sample(CPUTicks(user: 9, system: 100, idle: 100, nice: 100)) == nil)
}

@Test func signedCurrentHandlesNativeAndTwosComplementNumbers() {
    #expect(TelemetryMath.signedMilliamps(NSNumber(value: -1_000)) == -1_000)
    #expect(TelemetryMath.signedMilliamps(NSNumber(value: UInt32(bitPattern: -1_000))) == -1_000)
    #expect(TelemetryMath.signedMilliamps(NSNumber(value: UInt64(bitPattern: -1_000))) == -1_000)
    #expect(TelemetryMath.signedMilliamps(NSNumber(value: 1_000)) == 1_000)
    #expect(TelemetryMath.signedMilliamps(NSNumber(value: 0)) == 0)
    #expect(TelemetryMath.signedMilliamps(NSNumber(value: true)) == nil)
    #expect(TelemetryMath.signedMilliamps(NSNumber(value: 1.5)) == nil)
    #expect(TelemetryMath.signedMilliamps(nil) == nil)
}

@Test func batteryPowerPreservesSignAndUnknownVoltage() {
    #expect(TelemetryMath.batteryWatts(voltageMV: 12_000, currentMA: -1_000) == -12)
    #expect(TelemetryMath.batteryWatts(voltageMV: 12_000, currentMA: 1_000) == 12)
    #expect(TelemetryMath.batteryWatts(voltageMV: nil, currentMA: -1_000) == nil)
    #expect(TelemetryMath.batteryWatts(voltageMV: 0, currentMA: -1_000) == nil)
    #expect(TelemetryMath.batteryWatts(voltageMV: -1, currentMA: -1_000) == nil)
    #expect(TelemetryMath.batteryWatts(voltageMV: 12_000, currentMA: nil) == nil)
}

@Test func dischargeAverageWeightsElapsedTimeAndClipsWindow() {
    var average = RecentDischargeAverage(window: 10, maximumGap: 20, maximumSamples: 10)
    #expect(average.sample(watts: -10, at: 0, discharging: true) == nil)
    #expect(average.sample(watts: -20, at: 2, discharging: true) == 10)
    #expect(average.sample(watts: -30, at: 10, discharging: true) == 18)
    // Only 2...12 remains: eight seconds at 20 W and two at 30 W.
    #expect(average.sample(watts: -40, at: 12, discharging: true) == 22)
}

@Test func dischargeAverageCapsSamplesAndResetsChargingGapsAndBadData() {
    var average = RecentDischargeAverage(window: 100, maximumGap: 5, maximumSamples: 2)
    _ = average.sample(watts: -10, at: 0, discharging: true)
    _ = average.sample(watts: -20, at: 1, discharging: true)
    _ = average.sample(watts: -30, at: 2, discharging: true)
    #expect(average.sample(watts: -40, at: 3, discharging: true) == 25)
    #expect(average.sample(watts: 10, at: 4, discharging: false) == nil)
    #expect(average.sample(watts: -50, at: 5, discharging: true) == nil)
    #expect(average.sample(watts: -50, at: 11, discharging: true) == nil)
    #expect(average.sample(watts: -50, at: 12, discharging: true) == 50)
    #expect(average.sample(watts: nil, at: 13, discharging: true) == nil)
    #expect(average.sample(watts: -50, at: 14, discharging: true) == nil)
    #expect(average.sample(watts: -.infinity, at: 15, discharging: true) == nil)
    #expect(average.sample(watts: -20, at: 14, discharging: true) == nil)
}

@Test func thermalAlertsSkipStartupAvoidDowngradesAndRearmAfterCooling() {
    var alerts = ThermalAlertState()
    #expect((alerts.shouldAlert(.serious)) == false)
    #expect((alerts.shouldAlert(.serious)) == false)
    #expect((alerts.shouldAlert(.critical)) == true)
    #expect((alerts.shouldAlert(.serious)) == false)
    #expect((alerts.shouldAlert(.critical)) == false)
    #expect((alerts.shouldAlert(.fair)) == false)
    #expect((alerts.shouldAlert(.serious)) == true)
    #expect((alerts.shouldAlert(.unknown)) == false)
    #expect((alerts.shouldAlert(.serious)) == false)
    #expect((alerts.shouldAlert(.nominal)) == false)
    #expect((alerts.shouldAlert(.critical, enabled: false)) == false)
    #expect((alerts.shouldAlert(.critical)) == false)
}

@Test func telemetrySnapshotRoundTripsUnknownValuesAndKeepsAdapterDistinct() throws {
    let snapshot = TelemetrySnapshot(sampledAt: 42, battery: BatterySnapshot(),
        power: PowerTelemetry(batteryWatts: -12, averageDischargeWatts: nil, adapterWatts: 65, cycleCount: nil),
        compute: ComputeTelemetry(cpuFraction: nil, memoryUsedBytes: nil, memoryTotalBytes: 16_000_000_000,
            compressedBytes: nil, swapUsedBytes: nil, pressure: .unknown), thermal: .unknown)
    let data = try JSONEncoder().encode(snapshot)
    #expect(try JSONDecoder().decode(TelemetrySnapshot.self, from: data) == snapshot)
    #expect(snapshot.power?.adapterWatts == 65)
    #expect(snapshot.power?.batteryWatts == -12)
}
