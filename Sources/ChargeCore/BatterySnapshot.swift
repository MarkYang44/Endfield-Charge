import Foundation

public struct BatterySnapshot: Codable, Equatable {
    public var hasBattery: Bool
    public var percent: Int?
    public var externalPower: Bool
    public var isCharging: Bool
    public var isCharged: Bool
    public var currentMAh: Int?
    public var fullMAh: Int?
    public var voltageMV: Int?
    public var minutesRemaining: Int?
    public var lowPower: Bool

    public init(hasBattery: Bool = true, percent: Int? = nil, externalPower: Bool = false, isCharging: Bool = false, isCharged: Bool = false, currentMAh: Int? = nil, fullMAh: Int? = nil, voltageMV: Int? = nil, minutesRemaining: Int? = nil, lowPower: Bool = false) {
        self.hasBattery = hasBattery; self.percent = hasBattery ? percent.map { min(100, max(0, $0)) } : nil
        self.externalPower = externalPower; self.isCharging = isCharging; self.isCharged = isCharged
        self.currentMAh = hasBattery ? currentMAh : nil; self.fullMAh = hasBattery ? fullMAh : nil
        self.voltageMV = hasBattery ? voltageMV : nil; self.minutesRemaining = hasBattery ? minutesRemaining : nil; self.lowPower = lowPower
    }

    /// Approximate energy at the currently reported voltage, not a measured energy value.
    public var energyWh: Double? { energy(currentMAh) }
    public var fullEnergyWh: Double? { energy(fullMAh) }
    private func energy(_ capacity: Int?) -> Double? {
        guard hasBattery, let capacity, capacity >= 0, let voltageMV, voltageMV > 0 else { return nil }
        return Double(capacity) * Double(voltageMV) / 1_000_000
    }

    public static func from(description: [String: Any], registry: [String: Any], lowPower: Bool) -> BatterySnapshot {
        let present = (description["Is Present"] as? Bool) ?? (!description.isEmpty || !registry.isEmpty)
        guard present else { return BatterySnapshot(hasBattery: false, lowPower: lowPower) }
        func integer(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue }
        func capacityPair(current: Any?, full: Any?) -> (current: Int, full: Int)? {
            guard let current = integer(current), let full = integer(full),
                  full > 100, current >= 0, current <= full else { return nil }
            return (current, full)
        }
        let data = registry["BatteryData"] as? [String: Any] ?? [:]
        // A physical maximum establishes the unit for the entire pair, including a depleted current.
        // Never combine raw and nested readings: they can describe different capacity measurements.
        let capacities = capacityPair(current: registry["AppleRawCurrentCapacity"], full: registry["AppleRawMaxCapacity"])
            ?? capacityPair(current: data["RemainingCapacity"], full: data["FullChargeCapacity"])
            ?? capacityPair(current: data["RemainingCapacity"], full: data["NominalChargeCapacity"])
        let current = integer(description["Current Capacity"])
        let maximum = integer(description["Max Capacity"])
        let percent: Int? = current.flatMap { current in
            guard let maximum, maximum > 0 else { return nil }
            let ratio = Double(current) / Double(maximum) * 100
            return Int(min(100, max(0, ratio.rounded())))
        }
        let connected = (registry["ExternalConnected"] as? Bool) ?? (description["Power Source State"] as? String == "AC Power")
        let charging = description["Is Charging"] as? Bool ?? false
        let time = integer(description[charging ? "Time to Full Charge" : "Time to Empty"]).flatMap { $0 >= 0 ? $0 : nil }
        return BatterySnapshot(hasBattery: true, percent: percent, externalPower: connected, isCharging: charging,
            isCharged: (description["Is Charged"] as? Bool) ?? (registry["FullyCharged"] as? Bool) ?? false,
            currentMAh: capacities?.current, fullMAh: capacities?.full,
            voltageMV: integer(registry["Voltage"]).flatMap { $0 > 0 ? $0 : nil }, minutesRemaining: time, lowPower: lowPower)
    }
}
