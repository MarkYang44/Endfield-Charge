import AppKit
import ChargeCore

// Shared native fixtures; preferences always use disposable test suites.
let app = NSApplication.shared
let unicodeName = String(repeating: "👨‍👩‍👧‍👦", count: 32)
let byteMaximumName = String(repeating: "e\u{301}", count: 31) + "e" + String(repeating: "\u{301}", count: 465)
func maximumUnicodePreferences() -> Preferences {
    var value = Preferences()
    for _ in 0..<7 { value.capsuleProfiles.append(.custom(title: unicodeName)) }
    for index in value.capsuleProfiles.indices {
        if index >= 5 { value.capsuleProfiles[index].id = String(format: "%02d", index) + String(repeating: "i", count: 61) + "e" + String(repeating: "\u{301}", count: 96) }
        value.capsuleProfiles[index].title = byteMaximumName
        value.capsuleProfiles[index].colorConditions = CapsuleAccent.allCases.map {
            CapsuleColorCondition(metric: .networkDownloadBytesPerSecond, comparison: .above, threshold: 1, accent: $0)
        }
    }
    value.telemetryAlertRules = (0..<16).map { index in
        TelemetryAlertRule(id: String(format: "%02d", index) + String(repeating: "r", count: 61) + "e" + String(repeating: "\u{301}", count: 96), name: byteMaximumName, condition: index.isMultiple(of: 2) ? .threshold : .stateChange,
            source: index.isMultiple(of: 2) ? nil : .memoryPressure,
            targetState: index.isMultiple(of: 2) ? nil : .memoryPressure(.critical))
    }
    value.playback = CapsulePlayback(persistent: true, rotationEnabled: true,
        profileIDs: value.capsuleProfiles.map(\.id), intervalSeconds: 600)
    return value
}

func spin(_ seconds: Double) { autoreleasepool { RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds)) } }
func awaitCondition(_ condition: () -> Bool, _ message: String) {
    let deadline = Date(timeIntervalSinceNow: 2)
    while !condition() && Date() < deadline { spin(0.01) }
    check(condition(), message)
}
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

let telemetrySample = TelemetrySnapshot(sampledAt: 100,
    battery: BatterySnapshot(hasBattery: true, percent: 68, currentMAh: 3400, fullMAh: 5000, voltageMV: 12000),
    power: PowerTelemetry(batteryWatts: -12, averageDischargeWatts: 10, adapterWatts: nil, cycleCount: 26),
    compute: ComputeTelemetry(cpuFraction: 0.25, memoryUsedBytes: 8 * 1_073_741_824,
        memoryTotalBytes: 24 * 1_073_741_824, compressedBytes: 1_073_741_824,
        swapUsedBytes: 0, pressure: .normal), thermal: .fair)
