import Foundation
import Testing
@testable import ChargeCore

struct ChargeCoreTests {
    @Test func testPercentageNormalizationAndUnknownUnits() {
        let s = BatterySnapshot.from(description: ["Current Capacity": 120, "Max Capacity": 100, "Power Source State": "AC Power", "Is Charging": false], registry: [:], lowPower: false)
        #expect(s.percent == 100); #expect(s.externalPower); #expect(!(s.isCharging))
        #expect(s.currentMAh == nil); #expect(s.energyWh == nil)
        #expect(BatterySnapshot.from(description: ["Current Capacity": 3, "Max Capacity": 0], registry: [:], lowPower: false).percent == nil)
    }
    @Test func testPhysicalCapacityAndRegistryPowerPreference() {
        let s = BatterySnapshot.from(description: ["Current Capacity": 40, "Max Capacity": 80, "Power Source State": "Battery Power", "Is Charging": true], registry: ["ExternalConnected": true, "AppleRawCurrentCapacity": 2500, "AppleRawMaxCapacity": 5000, "Voltage": 12000], lowPower: true)
        #expect(s.percent == 50); #expect(s.externalPower); #expect(s.isCharging)
        #expect(s.energyWh == 30); #expect(s.fullEnergyWh == 60)
    }
    @Test func testNestedPhysicalCapacityFallback() {
        let s = BatterySnapshot.from(description: ["Current Capacity": -1, "Max Capacity": 100], registry: ["AppleRawCurrentCapacity": 50, "AppleRawMaxCapacity": 100, "BatteryData": ["RemainingCapacity": 2300, "FullChargeCapacity": 4800]], lowPower: false)
        #expect(s.percent == 0); #expect(s.currentMAh == 2300); #expect(s.fullMAh == 4800)
    }
    @Test func testDepletedRawPhysicalCapacitiesRemainAvailable() {
        for current in [0, 50] {
            let s = BatterySnapshot.from(description: [:], registry: ["AppleRawCurrentCapacity": current, "AppleRawMaxCapacity": 5000, "Voltage": 12000], lowPower: false)
            #expect(s.currentMAh == current)
            #expect(s.fullMAh == 5000)
            #expect(s.energyWh == Double(current) * 0.012)
        }
    }
    @Test func testDepletedNestedPhysicalCapacityRemainsAvailable() {
        let s = BatterySnapshot.from(description: [:], registry: ["BatteryData": ["RemainingCapacity": 50, "FullChargeCapacity": 4800]], lowPower: false)
        #expect(s.currentMAh == 50)
        #expect(s.fullMAh == 4800)
    }
    @Test func testCapacitySourcesNeverMixAndRejectInvalidPairs() {
        let registries: [[String: Any]] = [
            ["AppleRawCurrentCapacity": 2500, "BatteryData": ["FullChargeCapacity": 4800]],
            ["AppleRawMaxCapacity": 5000, "BatteryData": ["RemainingCapacity": 2500]],
            ["AppleRawCurrentCapacity": -1, "AppleRawMaxCapacity": 5000],
            ["AppleRawCurrentCapacity": 5100, "AppleRawMaxCapacity": 5000],
            ["BatteryData": ["RemainingCapacity": -1, "FullChargeCapacity": 4800]]
        ]
        for registry in registries {
            let s = BatterySnapshot.from(description: [:], registry: registry, lowPower: false)
            #expect(s.currentMAh == nil)
            #expect(s.fullMAh == nil)
        }
    }
    @Test func testInvalidRawPairFallsBackToCoherentNestedPair() {
        for current in [-1, 50, 6000] {
            let s = BatterySnapshot.from(description: [:], registry: ["AppleRawCurrentCapacity": current, "AppleRawMaxCapacity": 100, "BatteryData": ["RemainingCapacity": 50, "FullChargeCapacity": 4800]], lowPower: false)
            #expect(s.currentMAh == 50)
            #expect(s.fullMAh == 4800)
        }
    }
    @Test func testNoBatteryAndReadGapsRemainUnknown() {
        let s = BatterySnapshot.from(description: [:], registry: [:], lowPower: false)
        #expect(!(s.hasBattery)); #expect(s.percent == nil)
        var reducer = PowerEventReducer()
        #expect(reducer.consume(BatterySnapshot(percent: 60, externalPower: true)) == [])
        #expect(reducer.consume(s) == [])
        #expect(reducer.consume(BatterySnapshot(percent: 60, externalPower: true)) == [])
        #expect(reducer.consume(BatterySnapshot(percent: 60)) == [.disconnected])
    }
    @Test func testThresholdCrossingsAndUnknownPercentage() {
        var r = PowerEventReducer()
        #expect(r.consume(BatterySnapshot(percent: 30)) == [])
        #expect(r.consume(BatterySnapshot(percent: nil)) == [])
        #expect(r.consume(BatterySnapshot(percent: 19)) == [])
        #expect(r.consume(BatterySnapshot(percent: 25)) == [])
        #expect(r.consume(BatterySnapshot(percent: 20)) == [.lowBattery])
        #expect(r.consume(BatterySnapshot(percent: 19)) == [])
        #expect(r.consume(BatterySnapshot(percent: 18, externalPower: true)) == [.connected])
        #expect(r.consume(BatterySnapshot(percent: 17)) == [.disconnected])
    }
    @Test func testAbsentBatteryBreaksThresholdHistory() {
        var r = PowerEventReducer()
        #expect(r.consume(BatterySnapshot(percent: 30)) == [])
        #expect(r.consume(BatterySnapshot(hasBattery: false)) == [])
        #expect(r.consume(BatterySnapshot(percent: 10)) == [])
    }
    @Test func testFullChargeAndLowPowerTransitions() {
        var r = PowerEventReducer()
        #expect(r.consume(BatterySnapshot(percent: 98, externalPower: true)) == [])
        #expect(r.consume(BatterySnapshot(percent: 99, externalPower: true, lowPower: true)) == [.fullyCharged, .lowPowerEnabled])
        #expect(r.consume(BatterySnapshot(percent: 100, externalPower: true, isCharged: true, lowPower: true)) == [])
        #expect(r.consume(BatterySnapshot(percent: 95, externalPower: true)) == [.lowPowerDisabled])
        #expect(r.consume(BatterySnapshot(percent: 99, externalPower: true)) == [.fullyCharged])
    }
    @Test func testChargingAt99DoesNotReportCompletion() {
        var r = PowerEventReducer()
        #expect(r.consume(BatterySnapshot(percent: 98, externalPower: true, isCharging: true)) == [])
        #expect(r.consume(BatterySnapshot(percent: 99, externalPower: true, isCharging: true)) == [])
        #expect(r.consume(BatterySnapshot(percent: 100, externalPower: true, isCharging: true)) == [])
        #expect(r.consume(BatterySnapshot(percent: 99, externalPower: true, isCharging: false)) == [.fullyCharged])
    }
    @Test func testFullChargePercentageJitterDoesNotRepeatAlert() {
        var r = PowerEventReducer()
        #expect(r.consume(BatterySnapshot(percent: 98, externalPower: true)) == [])
        #expect(r.consume(BatterySnapshot(percent: 99, externalPower: true)) == [.fullyCharged])
        for percent in [98, 99, 96, 99] {
            #expect(r.consume(BatterySnapshot(percent: percent, externalPower: true)) == [])
        }
        #expect(r.consume(BatterySnapshot(percent: 95, externalPower: true, isCharged: true)) == [])
        #expect(r.consume(BatterySnapshot(percent: 99, externalPower: true)) == [])
        #expect(r.consume(BatterySnapshot(percent: 95, externalPower: true)) == [])
        #expect(r.consume(BatterySnapshot(percent: 99, externalPower: true)) == [.fullyCharged])
        #expect(r.consume(BatterySnapshot(percent: 99)) == [.disconnected])
        #expect(r.consume(BatterySnapshot(percent: 99, externalPower: true)) == [.connected, .fullyCharged])
    }
    @Test func testSnapshotCodableRoundtrip() throws {
        let s = BatterySnapshot(percent: 61, currentMAh: 2100, fullMAh: 4000, voltageMV: 11500)
        #expect(try JSONDecoder().decode(BatterySnapshot.self, from: JSONEncoder().encode(s)) == s)
    }
    @Test func testHUDReferenceStages() {
        #expect(HUDFrame.at(seconds: 0).pillOpacity == 0)
        let title = HUDFrame.at(seconds: 1.6)
        #expect(title.pillHeight == 90); #expect(title.titleOpacity == 1)
        let numbers = HUDFrame.at(seconds: 2.52)
        #expect(numbers.pillHeight == 60); #expect(numbers.numbersOpacity == 1)
        #expect(numbers.boltX == -245); #expect(numbers.squareMix == 1)
        #expect(HUDFrame.at(seconds: 6).overallScale == 0)
    }
    @Test func testHUDDurationAndReducedMotion() {
        for duration in [3.0, 6.0, 10.0] {
            #expect(HUDFrame.at(seconds: 2.52, duration: duration).numbersOpacity == 1)
            #expect(HUDFrame.at(seconds: duration - 0.4, duration: duration).overallScale == 1)
            #expect(HUDFrame.at(seconds: duration, duration: duration).pillOpacity == 0)
        }
        let reduced = HUDFrame.at(seconds: 1, reduceMotion: true)
        #expect(reduced.pillHeight == 60); #expect(reduced.numbersOpacity == 1)
        #expect(reduced.rippleOpacity == 0); #expect(reduced.pillScale == 1)
        #expect(reduced.titleOpacity > 0)
        #expect(reduced.titleOpacity == reduced.numbersOpacity)
    }
}
