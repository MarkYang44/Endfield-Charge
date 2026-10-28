import Foundation
import Testing
@testable import ChargeCore

private func page(_ tab: Int, _ zh: Bool = false, snapshot: TelemetrySnapshot? = nil,
                  preferences: Preferences = Preferences(), history: [TelemetryHistorySample] = [], demo: Bool = false) -> TelemetryPagePresentation {
    TelemetryPagePresentation(page: tab, preferences: preferences, snapshot: snapshot, chinese: zh, history: history, demo: demo)
}

@Test func telemetryEmptyPagesHaveLiteralLocalizedRows() {
    let english = [
        ["Battery energy (approx.)", "Battery level", "Battery-side power (approx.)", "Adapter-reported power", "Cycle count", "Recent discharge (approx.)"],
        ["CPU usage", "Memory used (approx.)", "Compressed memory", "Swap", "Memory pressure"],
        ["System thermal state", "Nominal", "Fair", "Serious", "Critical"],
        ["Download rate", "Upload rate", "Observed-session received", "Observed-session sent", "Enabled en* interfaces", "Interface count"],
        ["Filesystem total", "Used", "Free", "User available", "Filesystem", "Sampled volume path"]]
    let chinese = [
        ["电池能量（估算）", "电量", "电池侧功率（估算）", "适配器报告功率", "循环次数", "近期平均放电（估算）"],
        ["CPU 使用率", "内存使用（估算）", "压缩内存", "交换空间", "内存压力"],
        ["系统热状态", "正常", "稍热", "严重", "临界"],
        ["下载速率", "上传速率", "观测会话累计接收", "观测会话累计发送", "已启用 en* 接口", "接口数量"],
        ["文件系统总空间", "已使用", "空闲空间", "用户可用空间", "文件系统", "采样卷路径"]]
    for tab in 0..<5 {
        #expect(page(tab).rows.map(\.label) == english[tab])
        #expect(page(tab, true).rows.map(\.label) == chinese[tab])
        #expect(page(tab).rows.map(\.value) == (tab == 2 ? ["—", "Normal operation", "Mild thermal load", "Performance constrained", "Critical thermal load"] : Array(repeating: "—", count: english[tab].count)))
        #expect(page(tab).graphAccessibility == page(tab).caption + " · Up to 300 samples")
    }
    #expect(page(-1).rows == page(0).rows)
    #expect(page(99).rows == page(0).rows)
    #expect(page(0, demo: true).footer == "/// DEMO FIXTURE · NOT LIVE READINGS")
    #expect(page(0, true, demo: true).footer == "/// 演示数据 · 非本机读数")
    #expect(page(0).footer == "/// LOCAL SAMPLE · — MEANS UNAVAILABLE")
}

private func telemetryFixture() -> TelemetrySnapshot {
    TelemetrySnapshot(sampledAt: 42, battery: BatterySnapshot(percent: 50, currentMAh: 2000, fullMAh: 4000, voltageMV: 12000),
        power: PowerTelemetry(batteryWatts: -12.25, averageDischargeWatts: 8.75, adapterWatts: 65, cycleCount: 123),
        compute: ComputeTelemetry(cpuFraction: 0.125, memoryUsedBytes: 2147483648, memoryTotalBytes: 8589934592, compressedBytes: 1073741824, swapUsedBytes: 0, pressure: .warning),
        thermal: .serious,
        network: NetworkTelemetry(downloadBytesPerSecond: 1572864, uploadBytesPerSecond: 524288, receivedBytes: 2147483648, sentBytes: 1073741824, interfaces: ["en0", "en1"]),
        storage: StorageTelemetry(totalBytes: 8589934592, freeBytes: 2147483648, availableBytes: 1073741824, path: "/", fileSystem: "apfs"))
}

@Test func telemetryFormatsAndRangesPreserveOriginalPrecision() {
    let s = telemetryFixture()
    #expect(page(0, snapshot: s).rows.map(\.value) == ["≈24.0 Wh", "50 %", "≈-12.2 W", "65 W", "123", "≈8.8 W"])
    #expect(page(1, snapshot: s).rows.map(\.value) == ["12.5 %", "≈2.00 GiB / 8.00 GiB", "1.00 GiB", "0.00 GiB", "Warning"])
    #expect(page(2, snapshot: s).rows.map(\.value) == ["Serious", "Normal operation", "Mild thermal load", "Performance constrained", "Critical thermal load"])
    #expect(page(3, snapshot: s).rows.map(\.value) == ["1.50 MiB/s", "0.50 MiB/s", "2.00 GiB", "1.00 GiB", "en0, en1", "2"])
    #expect(page(4, snapshot: s).rows.map(\.value) == ["8.00 GiB", "6.00 GiB", "2.00 GiB", "1.00 GiB", "apfs", "/"])
    #expect(page(0).fixedRange == nil)
    #expect(page(3).fixedRange == nil)
    #expect(page(1).fixedRange == 0...1)
    #expect(page(2).fixedRange == 0...3)
    #expect(page(4).fixedRange == 0...1)
    #expect(page(2, snapshot: s).alert)
    #expect(page(2, snapshot: s).rows[0].alert)
    #expect(page(1, snapshot: s).rows[0].accessibility == "CPU usage: 12.5 %")
}

@Test func telemetryDisabledMissingNonfiniteAndNetworkBaseline() {
    var s = telemetryFixture()
    s.compute?.cpuFraction = .nan
    s.power?.batteryWatts = .infinity
    s.power?.averageDischargeWatts = .nan
    s.network?.uploadBytesPerSecond = nil
    #expect(page(0, snapshot: s).rows[2].value == "—")
    #expect(page(0, snapshot: s).rows[5].value == "—")
    #expect(page(1, snapshot: s).rows[0].value == "—")
    #expect(page(3, snapshot: s).rows.map(\.value) == ["1.50 MiB/s", "—", "—", "—", "en0, en1", "2"])
    var p = Preferences()
    p.powerTelemetryEnabled = false; p.computeTelemetryEnabled = false; p.thermalTelemetryEnabled = false
    p.networkTelemetryEnabled = false; p.storageTelemetryEnabled = false
    for tab in 0..<5 {
        let projection = page(tab, snapshot: s, preferences: p)
        #expect(projection.rows.allSatisfy { $0.value == "—" && !$0.alert })
        #expect(projection.samples.isEmpty)
        #expect(projection.status == "/// MODULE DISABLED · ENABLE IN SETTINGS")
        #expect(page(tab, true, preferences: p).status == "/// 此模块已停用 · 可在设置中启用")
    }
    #expect(page(2, snapshot: s, preferences: p).alert) // Original graph alert survives disabling.
}

@Test func telemetryStatesAndGraphSamplesRemainPaired() {
    var s = telemetryFixture()
    for (level, en, zh, number) in [(ThermalLevel.nominal, "Nominal", "正常", 0.0), (.fair, "Fair", "稍热", 1), (.serious, "Serious", "严重", 2), (.critical, "Critical", "临界", 3)] {
        s.thermal = level
        #expect(page(2, snapshot: s).rows[0].value == en)
        #expect(page(2, true, snapshot: s).rows[0].value == zh)
        #expect(TelemetryHistorySample(snapshot: s, preferences: Preferences()).thermal == number)
    }
    for (pressure, en, zh) in [(MemoryPressureLevel.normal, "Normal", "正常"), (.warning, "Warning", "警告"), (.critical, "Critical", "临界"), (.unknown, "—", "—")] {
        s.compute?.pressure = pressure
        #expect(page(1, snapshot: s).rows[4].value == en)
        #expect(page(1, true, snapshot: s).rows[4].value == zh)
    }
    s.thermal = .unknown
    #expect(page(2, snapshot: s).rows[0].value == "—")
    #expect(TelemetryHistorySample(snapshot: s, preferences: Preferences()).thermal == nil)
    let first = TelemetryHistorySample(snapshot: s, preferences: Preferences())
    s.sampledAt = 44; s.network?.downloadBytesPerSecond = nil; s.network?.uploadBytesPerSecond = 7
    let second = TelemetryHistorySample(snapshot: s, preferences: Preferences())
    let samples = page(3, history: [first, second]).samples
    #expect(samples == [TelemetryGraphSample(time: 42, primary: 1572864, secondary: 524288), TelemetryGraphSample(time: 44, primary: nil, secondary: 7)])
}

@Test func telemetryLocalizedPageCopyAndChineseValues() {
    let captions = [
        ("/// RECENT BATTERY-SIDE POWER", "/// 近期电池侧功率"),
        ("/// RECENT CPU USAGE", "/// 近期 CPU 使用率"),
        ("/// RECENT SYSTEM THERMAL STATE", "/// 近期系统热状态"),
        ("/// DOWNLOAD ↓ LIME / UPLOAD ↑ GRAY · TOTALS RESET WITH SESSION", "/// 下载 ↓ 黄绿 / 上传 ↑ 灰 · 会话重置后重新累计"),
        ("/// RECENT FILESYSTEM USED FRACTION · NO SSD WEAR READING", "/// 近期文件系统占用比例 · 非 SSD 磨损读数")]
    let statuses = [
        ("/// BATTERY + CHARGING / − DISCHARGING · ADAPTER IS SEPARATE", "/// 电池侧 + 充电 / − 放电 · 与适配器功率不同"),
        ("/// MEMORY ESTIMATE = ACTIVE + WIRED + COMPRESSED", "/// 内存估算 = 活跃 + 不可换出 + 压缩"),
        ("/// PUBLIC SYSTEM STATE · NO MEASURED TEMPERATURE", "/// 系统公开状态 · 不代表实测温度"),
        ("/// ENABLED en* · INCLUDES LAN, EXCLUDES VPN/LOOPBACK · NOT CONNECTIVITY", "/// 已启用 en* · 含局域网，排除 VPN/回环 · 非联网状态"),
        ("/// APFS SHARED CONTAINER SPACE · VOLUMES ARE NOT SUMMED", "/// APFS 共享容器空间 · 不重复累加卷容量")]
    let values = [
        ["≈24.0 Wh", "50 %", "≈-12.2 W", "65 W", "123", "≈8.8 W"],
        ["12.5 %", "≈2.00 GiB / 8.00 GiB", "1.00 GiB", "0.00 GiB", "警告"],
        ["严重", "系统运行正常", "系统轻度升温", "系统限制性能", "热负载达到临界"],
        ["1.50 MiB/s", "0.50 MiB/s", "2.00 GiB", "1.00 GiB", "en0, en1", "2"],
        ["8.00 GiB", "6.00 GiB", "2.00 GiB", "1.00 GiB", "apfs", "/"]]
    for tab in 0..<5 {
        #expect(page(tab).caption == captions[tab].0)
        #expect(page(tab, true).caption == captions[tab].1)
        #expect(page(tab).status == statuses[tab].0)
        #expect(page(tab, true).status == statuses[tab].1)
        #expect(page(tab, true, snapshot: telemetryFixture()).rows.map(\.value) == values[tab])
        #expect(page(tab, true).graphAccessibility == captions[tab].1 + " · 最多 300 个采样")
    }
    #expect(page(0, true).footer == "/// 本机采样 · — 表示暂不可用")
}

@Test func telemetryProjectionKeepsMissingNonfiniteAndDiscontinuousSamplesForDrawing() {
    var s = telemetryFixture()
    let times = [0.0, 60, 121, 121, 120, 122, 124]
    let readings: [Double?] = [1, 2, nil, 3, .nan, .infinity, -4]
    let history = zip(times, readings).map { time, reading in
        s.sampledAt = time; s.power?.batteryWatts = reading
        return TelemetryHistorySample(snapshot: s, preferences: Preferences())
    }
    let samples = page(0, history: history).samples
    #expect(samples.map(\.time) == times)
    #expect(samples[0].primary == 1)
    #expect(samples[2].primary == nil)
    #expect(samples[4].primary?.isNaN == true)
    #expect(samples[5].primary == .infinity)
    #expect(samples[6].primary == -4)
    #expect(samples.allSatisfy { $0.secondary == nil })
    var disabled = Preferences()
    disabled.powerTelemetryEnabled = false
    let sample = TelemetryHistorySample(snapshot: s, preferences: disabled)
    #expect(page(0, history: [sample]).samples.first?.primary == nil)
}
