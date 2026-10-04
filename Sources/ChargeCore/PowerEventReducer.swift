public enum PowerEvent: String, Codable {
    case connected, disconnected, lowBattery, fullyCharged, lowPowerEnabled, lowPowerDisabled
}

public struct PowerEventReducer {
    private var previous: BatterySnapshot?
    private var fullAlerted = false
    public init() {}

    public mutating func consume(_ snapshot: BatterySnapshot, lowThreshold: Int = 20) -> [PowerEvent] {
        // An absent battery can be a transient IOKit read gap. Retain the last valid source.
        guard snapshot.hasBattery else {
            previous?.percent = nil
            return []
        }
        let full = snapshot.externalPower && (snapshot.isCharged || (!snapshot.isCharging && (snapshot.percent.map { $0 >= 99 } ?? false)))
        guard let previous else {
            self.previous = snapshot; fullAlerted = full; return []
        }
        var events: [PowerEvent] = []
        if previous.externalPower != snapshot.externalPower {
            events.append(snapshot.externalPower ? .connected : .disconnected)
        }
        let threshold = min(100, max(0, lowThreshold))
        if !snapshot.externalPower, !previous.externalPower,
           let old = previous.percent, let new = snapshot.percent, old > threshold, new <= threshold {
            events.append(.lowBattery)
        }
        if full && !fullAlerted { events.append(.fullyCharged); fullAlerted = true }
        if !snapshot.externalPower || (!snapshot.isCharged && snapshot.percent.map { $0 <= 95 } == true) { fullAlerted = false }
        if previous.lowPower != snapshot.lowPower { events.append(snapshot.lowPower ? .lowPowerEnabled : .lowPowerDisabled) }
        self.previous = snapshot
        return events
    }
}
