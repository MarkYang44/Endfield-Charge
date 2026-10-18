import Foundation
import ChargeCore

/// Shared display conversion. Persistence and rule evaluation always use metric base units.
enum TelemetryFormatting {
    static func name(_ metric: TelemetryMetric, chinese: Bool) -> String {
        let names: (String, String)
        switch metric {
        case .batteryEnergyWh: names = ("电池能量", "Battery energy")
        case .batteryPercent: names = ("电池电量", "Battery charge")
        case .cpuPercent: names = ("CPU 占用", "CPU usage")
        case .memoryUsedBytes: names = ("内存使用", "Memory used")
        case .memoryPercent: names = ("内存占用", "Memory usage")
        case .networkDownloadBytesPerSecond: names = ("下载速率", "Download")
        case .networkUploadBytesPerSecond: names = ("上传速率", "Upload")
        case .storageAvailableBytes: names = ("存储可用", "Storage available")
        case .storageUsedPercent: names = ("存储占用", "Storage used")
        }
        return chinese ? names.0 : names.1
    }
    static func unit(_ metric: TelemetryMetric) -> String {
        switch metric {
        case .batteryEnergyWh: return "Wh"
        case .batteryPercent, .cpuPercent, .memoryPercent, .storageUsedPercent: return "%"
        case .networkDownloadBytesPerSecond, .networkUploadBytesPerSecond: return "MiB/s"
        case .memoryUsedBytes, .storageAvailableBytes: return "GiB"
        }
    }
    static func scale(_ metric: TelemetryMetric) -> Double {
        switch metric {
        case .networkDownloadBytesPerSecond, .networkUploadBytesPerSecond: return 1_048_576
        case .memoryUsedBytes, .storageAvailableBytes: return 1_073_741_824
        default: return 1
        }
    }
    static func displayValue(_ baseValue: Double, metric: TelemetryMetric) -> Double { baseValue / scale(metric) }
    static func baseValue(_ displayValue: Double, metric: TelemetryMetric) -> Double { displayValue * scale(metric) }
    static func value(_ baseValue: Double?, metric: TelemetryMetric) -> String {
        guard let baseValue, baseValue.isFinite, baseValue >= 0 else { return "—" }
        let value = displayValue(baseValue, metric: metric)
        guard value < 1_000_000 else { return String(format: "%.1e", value) }
        return String(format: metric == .batteryEnergyWh ? "≈%.1f" : "%.1f", value)
    }
}

struct CapsulePresentation: Equatable {
    let profile: CapsuleProfile
    let title: String
    let primary: String
    let primaryUnit: String
    let secondary: String
    let secondaryUnit: String
    let ringFraction: Double?
    let alert: Bool

    init(profile: CapsuleProfile, snapshot: TelemetrySnapshot?, alert: Bool = false) {
        self.profile = profile
        title = String(profile.title.prefix(32))
        primary = TelemetryFormatting.value(snapshot.flatMap { profile.primaryMetric.value(in: $0) }, metric: profile.primaryMetric)
        primaryUnit = TelemetryFormatting.unit(profile.primaryMetric)
        if let metric = profile.secondaryMetric {
            secondary = TelemetryFormatting.value(snapshot.flatMap { metric.value(in: $0) }, metric: metric)
            secondaryUnit = TelemetryFormatting.unit(metric)
        } else { secondary = ""; secondaryUnit = "" }
        ringFraction = profile.ringMetric.flatMap { metric in
            snapshot.flatMap { metric.value(in: $0) }.map { min(1, max(0, $0 / profile.referenceMaximum)) }
        }
        self.alert = alert
    }
}

struct TelemetryDemand: Equatable {
    let power: Bool
    let compute: Bool
    let thermal: Bool
    let network: Bool
    let storage: Bool
    let highFrequency: Bool
    let batterySnapshot: Bool
    var hasWork: Bool { power || compute || thermal || network || storage || batterySnapshot }

    init(preferences: Preferences, panelVisible: Bool, capsuleMetrics: Set<TelemetryMetric>) {
        let rules = preferences.telemetryAlertRules.prefix(16).filter(\.enabled).map(\.metric)
        let metrics = capsuleMetrics.union(rules)
        batterySnapshot = metrics.contains(.batteryEnergyWh) || metrics.contains(.batteryPercent)
        power = preferences.powerTelemetryEnabled
        compute = preferences.computeTelemetryEnabled
        thermal = preferences.thermalTelemetryEnabled
        network = preferences.networkTelemetryEnabled && (panelVisible || metrics.contains(.networkDownloadBytesPerSecond)
            || metrics.contains(.networkUploadBytesPerSecond))
        storage = preferences.storageTelemetryEnabled && (panelVisible || metrics.contains(.storageAvailableBytes)
            || metrics.contains(.storageUsedPercent))
        highFrequency = panelVisible || !capsuleMetrics.isEmpty
    }
}
