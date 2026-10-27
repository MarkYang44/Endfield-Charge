import Foundation

/// Finite local metric catalog. Percent metrics use 0...100; byte rates use bytes/second.
public enum TelemetryMetric: String, Codable, CaseIterable {
    case batteryEnergyWh, batteryPercent, cpuPercent, memoryUsedBytes, memoryPercent
    case networkDownloadBytesPerSecond, networkUploadBytesPerSecond, storageAvailableBytes, storageUsedPercent

    public func value(in snapshot: TelemetrySnapshot) -> Double? {
        let result: Double?
        switch self {
        case .batteryEnergyWh: result = snapshot.battery.energyWh
        case .batteryPercent: result = snapshot.battery.hasBattery ? snapshot.battery.percent.map(Double.init) : nil
        case .cpuPercent: result = snapshot.compute?.cpuFraction.map { $0 * 100 }
        case .memoryUsedBytes: result = snapshot.compute?.memoryUsedBytes.map(Double.init)
        case .memoryPercent:
            if let compute = snapshot.compute, compute.memoryTotalBytes > 0, let used = compute.memoryUsedBytes {
                result = Double(used) / Double(compute.memoryTotalBytes) * 100
            } else { result = nil }
        case .networkDownloadBytesPerSecond: result = snapshot.network?.downloadBytesPerSecond
        case .networkUploadBytesPerSecond: result = snapshot.network?.uploadBytesPerSecond
        case .storageAvailableBytes: result = snapshot.storage.map { Double($0.availableBytes) }
        case .storageUsedPercent: result = snapshot.storage.map { $0.usedFraction * 100 }
        }
        return result.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }
}

public struct CapsuleProfile: Codable, Equatable, Identifiable {
    public static let batteryID = "builtin.battery"
    public static let cpuID = "builtin.cpu"
    public static let memoryID = "builtin.memory"
    public static let networkID = "builtin.network"
    public static let storageID = "builtin.storage"
    public var id: String
    public var title: String
    public var primaryMetric: TelemetryMetric
    public var secondaryMetric: TelemetryMetric?
    public var ringMetric: TelemetryMetric?
    public var referenceMaximum: Double
    public var colorConditions: [CapsuleColorCondition]
    /// Preserve the original battery renderer only for the unchanged built-in configuration.
    public var isDefaultBattery: Bool { self == Self.defaults[0] }
    /// Palette changes retain the original battery geometry and animation.
    public var isBatteryLayout: Bool {
        var uncolored = self; uncolored.colorConditions = []
        return uncolored.isDefaultBattery
    }
    public func resolvedAccent(in snapshot: TelemetrySnapshot) -> CapsuleAccent {
        colorConditions.prefix(ConfigurationLimits.maximumColorConditions).first { $0.matches(in: snapshot) }?.accent ?? .theme
    }

    public init(id: String, title: String, primaryMetric: TelemetryMetric,
                secondaryMetric: TelemetryMetric? = nil, ringMetric: TelemetryMetric? = nil,
                referenceMaximum: Double = 100, colorConditions: [CapsuleColorCondition] = []) {
        self.id = id; self.title = title; self.primaryMetric = primaryMetric
        self.secondaryMetric = secondaryMetric; self.ringMetric = ringMetric
        self.referenceMaximum = referenceMaximum; self.colorConditions = colorConditions
        normalize()
    }
    /// UUIDs are generated only in response to explicit creation, never during migration/defaults.
    public static func custom(title: String = "CUSTOM", primaryMetric: TelemetryMetric = .cpuPercent) -> Self {
        Self(id: UUID().uuidString, title: title, primaryMetric: primaryMetric)
    }
    public mutating func normalize() {
        id = ConfigurationTextLimit.identifier.bounded(id)
        title = ConfigurationTextLimit.name.bounded(title)
        if title.isEmpty { title = "CUSTOM" }
        colorConditions = Array(colorConditions.prefix(ConfigurationLimits.maximumColorConditions).filter { $0.threshold.isFinite })
        if !referenceMaximum.isFinite || referenceMaximum <= 0 { referenceMaximum = 100 }
    }
    public static var defaults: [Self] {
        [Self(id: batteryID, title: "BATTERY", primaryMetric: .batteryEnergyWh, secondaryMetric: .batteryPercent, ringMetric: .batteryPercent),
         Self(id: cpuID, title: "CPU", primaryMetric: .cpuPercent, ringMetric: .cpuPercent),
         Self(id: memoryID, title: "MEMORY", primaryMetric: .memoryUsedBytes, secondaryMetric: .memoryPercent, ringMetric: .memoryPercent),
         Self(id: networkID, title: "NETWORK", primaryMetric: .networkDownloadBytesPerSecond, secondaryMetric: .networkUploadBytesPerSecond),
         Self(id: storageID, title: "STORAGE", primaryMetric: .storageAvailableBytes, secondaryMetric: .storageUsedPercent, ringMetric: .storageUsedPercent)]
    }
    private enum CodingKeys: String, CodingKey { case id, title, primaryMetric, secondaryMetric, ringMetric, referenceMaximum, colorConditions }
    public init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try v.decodeIfPresent(String.self, forKey: .id) ?? "", title: try v.decodeIfPresent(String.self, forKey: .title) ?? "CUSTOM",
            primaryMetric: try v.decode(TelemetryMetric.self, forKey: .primaryMetric),
            secondaryMetric: try v.decodeIfPresent(TelemetryMetric.self, forKey: .secondaryMetric),
            ringMetric: try v.decodeIfPresent(TelemetryMetric.self, forKey: .ringMetric),
            referenceMaximum: try v.decodeIfPresent(Double.self, forKey: .referenceMaximum) ?? 100,
            colorConditions: (try? v.decodeIfPresent(BoundedColorConditions.self, forKey: .colorConditions))?.items ?? [])
    }
}

private struct BoundedColorConditions: Decodable {
    var items: [CapsuleColorCondition] = []
    init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        for _ in 0..<ConfigurationLimits.maximumColorConditions where !values.isAtEnd {
            let entry = try values.superDecoder()
            if let value = try? CapsuleColorCondition(from: entry) { items.append(value) }
        }
    }
}
