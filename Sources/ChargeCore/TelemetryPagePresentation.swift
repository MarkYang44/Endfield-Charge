import Foundation

/// Only the original plotted fields are retained by the on-demand native view.
public struct TelemetryHistorySample {
    public let time: Double
    public let power: Double?
    public let cpu: Double?
    public let thermal: Double?
    public let download: Double?
    public let upload: Double?
    public let storage: Double?

    public init(snapshot: TelemetrySnapshot, preferences: Preferences) {
        self.time = snapshot.sampledAt
        self.power = preferences.powerTelemetryEnabled ? snapshot.power?.batteryWatts : nil
        self.cpu = preferences.computeTelemetryEnabled ? snapshot.compute?.cpuFraction : nil
        self.thermal = preferences.thermalTelemetryEnabled ? thermalNumber(snapshot.thermal) : nil
        self.download = preferences.networkTelemetryEnabled ? snapshot.network?.downloadBytesPerSecond : nil
        self.upload = preferences.networkTelemetryEnabled ? snapshot.network?.uploadBytesPerSecond : nil
        self.storage = preferences.storageTelemetryEnabled ? snapshot.storage?.usedFraction : nil
    }
}

/// A timestamp and both series travel together, including missing readings.
public struct TelemetryGraphSample: Equatable {
    public let time: Double
    public let primary: Double?
    public let secondary: Double?

    public init(time: Double, primary: Double?, secondary: Double? = nil) {
        self.time = time; self.primary = primary; self.secondary = secondary
    }
}

public struct TelemetryPageRow: Equatable {
    public let label: String
    public let value: String
    public let alert: Bool
    public var accessibility: String { label + ": " + value }
}

/// A pure, localized value projection. AppKit retains drawing, controls and history ownership.
public struct TelemetryPagePresentation {
    public let rows: [TelemetryPageRow]
    public let status: String
    public let caption: String
    public let footer: String
    public let samples: [TelemetryGraphSample]
    public let fixedRange: ClosedRange<Double>?
    public let alert: Bool
    public let graphAccessibility: String

    public init(page: Int, preferences: Preferences, snapshot: TelemetrySnapshot?, chinese: Bool,
                history: [TelemetryHistorySample], demo: Bool) {
        let selectedPage = (0..<5).contains(page) ? page : 0
        func t(_ zh: String, _ en: String) -> String { localized(chinese, zh, en) }
        let names: [String]
        switch selectedPage {
        case 1: names = [t("CPU 使用率", "CPU usage"), t("内存使用（估算）", "Memory used (approx.)"),
            t("压缩内存", "Compressed memory"), t("交换空间", "Swap"), t("内存压力", "Memory pressure")]
        case 2: names = [t("系统热状态", "System thermal state"), t("正常", "Nominal"), t("稍热", "Fair"),
            t("严重", "Serious"), t("临界", "Critical")]
        case 3: names = [t("下载速率", "Download rate"), t("上传速率", "Upload rate"),
            t("观测会话累计接收", "Observed-session received"), t("观测会话累计发送", "Observed-session sent"),
            t("已启用 en* 接口", "Enabled en* interfaces"), t("接口数量", "Interface count")]
        case 4: names = [t("文件系统总空间", "Filesystem total"), t("已使用", "Used"), t("空闲空间", "Free"),
            t("用户可用空间", "User available"), t("文件系统", "Filesystem"), t("采样卷路径", "Sampled volume path")]
        default: names = [t("电池能量（估算）", "Battery energy (approx.)"), t("电量", "Battery level"),
            t("电池侧功率（估算）", "Battery-side power (approx.)"), t("适配器报告功率", "Adapter-reported power"),
            t("循环次数", "Cycle count"), t("近期平均放电（估算）", "Recent discharge (approx.)")]
        }
        let enabled: Bool
        let values: [String]
        var samples: [TelemetryGraphSample] = []
        var fixedRange: ClosedRange<Double>?
        let caption: String
        var status: String
        switch selectedPage {
        case 1:
            enabled = preferences.computeTelemetryEnabled
            let c = snapshot?.compute
            values = [c?.cpuFraction.flatMap { $0.isFinite ? String(format: "%.1f %%", $0 * 100) : nil } ?? "—",
                c?.memoryUsedBytes.map { "≈" + bytes($0) + " / " + bytes(c?.memoryTotalBytes ?? 0) } ?? "—",
                c?.compressedBytes.map(bytes) ?? "—", c?.swapUsedBytes.map(bytes) ?? "—", pressureText(c?.pressure, chinese: chinese)]
            samples = enabled ? history.map { TelemetryGraphSample(time: $0.time, primary: $0.cpu, secondary: nil) } : []
            fixedRange = 0...1
            caption = t("/// 近期 CPU 使用率", "/// RECENT CPU USAGE")
            status = t("/// 内存估算 = 活跃 + 不可换出 + 压缩", "/// MEMORY ESTIMATE = ACTIVE + WIRED + COMPRESSED")
        case 2:
            enabled = preferences.thermalTelemetryEnabled
            let thermal = snapshot?.thermal
            values = [thermalText(thermal, chinese: chinese), t("系统运行正常", "Normal operation"), t("系统轻度升温", "Mild thermal load"),
                t("系统限制性能", "Performance constrained"), t("热负载达到临界", "Critical thermal load")]
            samples = enabled ? history.map { TelemetryGraphSample(time: $0.time, primary: $0.thermal, secondary: nil) } : []
            fixedRange = 0...3
            caption = t("/// 近期系统热状态", "/// RECENT SYSTEM THERMAL STATE")
            status = t("/// 系统公开状态 · 不代表实测温度", "/// PUBLIC SYSTEM STATE · NO MEASURED TEMPERATURE")
        case 3:
            enabled = preferences.networkTelemetryEnabled
            let n = snapshot?.network
            let observed = n?.downloadBytesPerSecond != nil && n?.uploadBytesPerSecond != nil
            values = [rate(n?.downloadBytesPerSecond), rate(n?.uploadBytesPerSecond),
                observed ? n.map { bytes($0.receivedBytes) } ?? "—" : "—",
                observed ? n.map { bytes($0.sentBytes) } ?? "—" : "—",
                n.map { $0.interfaces.isEmpty ? "—" : $0.interfaces.joined(separator: ", ") } ?? "—",
                n.map { String($0.interfaceCount) } ?? "—"]
            samples = enabled ? history.map { TelemetryGraphSample(time: $0.time, primary: $0.download, secondary: $0.upload) } : []
            fixedRange = nil
            caption = t("/// 下载 ↓ 黄绿 / 上传 ↑ 灰 · 会话重置后重新累计", "/// DOWNLOAD ↓ LIME / UPLOAD ↑ GRAY · TOTALS RESET WITH SESSION")
            status = t("/// 已启用 en* · 含局域网，排除 VPN/回环 · 非联网状态", "/// ENABLED en* · INCLUDES LAN, EXCLUDES VPN/LOOPBACK · NOT CONNECTIVITY")
        case 4:
            enabled = preferences.storageTelemetryEnabled
            let s = snapshot?.storage
            values = [s.map { bytes($0.totalBytes) } ?? "—", s.map { bytes($0.usedBytes) } ?? "—",
                s.map { bytes($0.freeBytes) } ?? "—", s.map { bytes($0.availableBytes) } ?? "—",
                s?.fileSystem ?? "—", s?.path ?? "—"]
            samples = enabled ? history.map { TelemetryGraphSample(time: $0.time, primary: $0.storage, secondary: nil) } : []
            fixedRange = 0...1
            caption = t("/// 近期文件系统占用比例 · 非 SSD 磨损读数", "/// RECENT FILESYSTEM USED FRACTION · NO SSD WEAR READING")
            status = t("/// APFS 共享容器空间 · 不重复累加卷容量", "/// APFS SHARED CONTAINER SPACE · VOLUMES ARE NOT SUMMED")
        default:
            enabled = preferences.powerTelemetryEnabled
            let b = snapshot?.battery, p = snapshot?.power
            values = [b?.energyWh.map { String(format: "≈%.1f Wh", $0) } ?? "—",
                b?.percent.map { "\($0) %" } ?? "—", watts(p?.batteryWatts, signed: true),
                p?.adapterWatts.map { "\($0) W" } ?? "—", p?.cycleCount.map(String.init) ?? "—", watts(p?.averageDischargeWatts)]
            samples = enabled ? history.map { TelemetryGraphSample(time: $0.time, primary: $0.power, secondary: nil) } : []
            fixedRange = nil
            caption = t("/// 近期电池侧功率", "/// RECENT BATTERY-SIDE POWER")
            status = t("/// 电池侧 + 充电 / − 放电 · 与适配器功率不同", "/// BATTERY + CHARGING / − DISCHARGING · ADAPTER IS SEPARATE")
        }

        rows = names.enumerated().map { index, name in
            TelemetryPageRow(label: name, value: enabled ? values[index] : "—",
                alert: selectedPage == 2 && index == 0 && enabled
                    && (snapshot?.thermal == .serious || snapshot?.thermal == .critical))
        }
        if !enabled { status = t("/// 此模块已停用 · 可在设置中启用", "/// MODULE DISABLED · ENABLE IN SETTINGS") }
        self.status = status
        self.caption = caption
        self.samples = samples
        self.fixedRange = fixedRange
        alert = selectedPage == 2 && (snapshot?.thermal == .serious || snapshot?.thermal == .critical)
        graphAccessibility = caption + " · " + t("最多 300 个采样", "Up to 300 samples")
        footer = demo ? t("/// 演示数据 · 非本机读数", "/// DEMO FIXTURE · NOT LIVE READINGS")
            : t("/// 本机采样 · — 表示暂不可用", "/// LOCAL SAMPLE · — MEANS UNAVAILABLE")
    }
}

private func localized(_ chinese: Bool, _ zh: String, _ en: String) -> String { chinese ? zh : en }

private func rate(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    return String(format: "%.2f MiB/s", value / 1_048_576)
}
private func watts(_ value: Double?, signed: Bool = false) -> String {
    guard let value, value.isFinite else { return "—" }
    return String(format: signed ? "≈%+.1f W" : "≈%.1f W", value)
}
private func bytes(_ value: UInt64) -> String { String(format: "%.2f GiB", Double(value) / 1_073_741_824) }
private func pressureText(_ pressure: MemoryPressureLevel?, chinese: Bool) -> String {
    switch pressure {
    case .normal: return localized(chinese, "正常", "Normal")
    case .warning: return localized(chinese, "警告", "Warning")
    case .critical: return localized(chinese, "临界", "Critical")
    default: return "—"
    }
}
private func thermalText(_ thermal: ThermalLevel?, chinese: Bool) -> String {
    switch thermal {
    case .nominal: return localized(chinese, "正常", "Nominal")
    case .fair: return localized(chinese, "稍热", "Fair")
    case .serious: return localized(chinese, "严重", "Serious")
    case .critical: return localized(chinese, "临界", "Critical")
    default: return "—"
    }
}
private func thermalNumber(_ thermal: ThermalLevel?) -> Double? {
    switch thermal {
    case .nominal: return 0
    case .fair: return 1
    case .serious: return 2
    case .critical: return 3
    default: return nil
    }
}
