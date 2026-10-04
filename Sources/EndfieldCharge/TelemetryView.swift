import AppKit
import ChargeCore

private struct TelemetryGraphPoint {
    let time: Double
    let power: Double?
    let cpu: Double?
    let thermal: Double?
}

private final class TelemetryPage: NSView {
    override var isFlipped: Bool { true }
}

private final class TelemetrySegmentCell: NSSegmentedCell {
    override func draw(withFrame frame: NSRect, in controlView: NSView) {
        // Newer AppKit appearances can ignore selectedSegmentBezelColor. Keep native tracking
        // and accessibility, while painting the reference palette deterministically.
        NSColor(rgb: 0x312F30).setFill()
        NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6).fill()
        guard segmentCount > 0 else { return }
        let width = (frame.width - 2) / CGFloat(segmentCount)
        for segment in 0..<segmentCount {
            let rect = NSRect(x: frame.minX + 1 + CGFloat(segment) * width, y: frame.minY + 1,
                width: width, height: frame.height - 2)
            if isSelected(forSegment: segment) {
                NSColor(rgb: 0xC6CA4C).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            }
            drawSegment(segment, inFrame: rect, with: controlView)
        }
    }

    override func drawSegment(_ segment: Int, inFrame frame: NSRect, with controlView: NSView) {
        let text = label(forSegment: segment) ?? ""
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: isSelected(forSegment: segment) ? NSColor(rgb: 0x141313) : NSColor(rgb: 0xE9E7E4)
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2),
            withAttributes: attributes)
    }
}

private final class TelemetryGraph: NSView {
    override var isFlipped: Bool { true }
    var values: [Double?] = []
    var times: [Double] = []
    var fixedRange: ClosedRange<Double>?
    var alert = false

    override func draw(_ dirtyRect: NSRect) {
        NSColor(rgb: 0x312F30).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        let rect = bounds.insetBy(dx: 8, dy: 7)
        let finite = values.compactMap { $0 }.filter(\.isFinite)
        guard !finite.isEmpty, let firstTime = times.first else { return }
        let lower = fixedRange?.lowerBound ?? min(0, finite.min() ?? 0)
        let upper = fixedRange?.upperBound ?? max(1, finite.max() ?? 1)
        let span = max(0.001, upper - lower)
        let timeSpan = max(0.001, (times.last ?? firstTime) - firstTime)
        let path = NSBezierPath()
        var connected = false
        var previousTime: Double?
        for (time, value) in zip(times, values) {
            guard let value, value.isFinite else { connected = false; continue }
            // Public samples arrive every 2s/30s; a long sleep or clock reset must not imply continuous observations.
            if let previousTime, time <= previousTime || time - previousTime > 60 { connected = false }
            let point = NSPoint(x: rect.minX + CGFloat((time - firstTime) / timeSpan) * rect.width,
                y: rect.maxY - CGFloat(min(1, max(0, (value - lower) / span))) * rect.height)
            if connected { path.line(to: point) } else { path.move(to: point) }
            connected = true
            previousTime = time
            // A single reading should be visible before a second sample arrives.
            NSColor(rgb: alert ? 0xFF4D4F : 0xC6CA4C).setFill()
            NSBezierPath(ovalIn: NSRect(x: point.x - 1.4, y: point.y - 1.4, width: 2.8, height: 2.8)).fill()
        }
        NSColor(rgb: alert ? 0xFF4D4F : 0xC6CA4C).setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }
}

/// Native rows surround the unmodified upstream HUD renderer; only this on-demand view owns graph history.
final class TelemetryView: NSView {
    static let canvasSize = NSSize(width: 620, height: 560)
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    let header = HUDView(frame: NSRect(x: 0, y: 0, width: 620, height: 144))
    let settings: AppSettings
    var selectedTab: Int {
        didSet {
            if !(0..<3).contains(selectedTab) { selectedTab = 0 }
            if selectedTab != oldValue { rebuildPage() }
        }
    }
    var headerTimerActive: Bool { headerTimer != nil }
    var graphSampleCount: Int { history.count }
    private let onPreview: () -> Void
    private let tabs = NSSegmentedControl()
    private let page = TelemetryPage()
    private let graph = TelemetryGraph()
    private let graphCaption = NSTextField(labelWithString: "")
    private let status = NSTextField(labelWithString: "")
    private let footer = NSTextField(labelWithString: "")
    private let preview = NSButton()
    private var rows: [(label: NSTextField, value: NSTextField)] = []
    private var snapshot: TelemetrySnapshot?
    private var history: [TelemetryGraphPoint] = []
    private var headerTimer: Timer?
    private var headerStart = 0.0
    private var renderedChinese = false
    private var demo = false

    init(settings: AppSettings, selectedTab: Int = 0, onPreview: @escaping () -> Void = {}) {
        self.settings = settings
        self.selectedTab = (0..<3).contains(selectedTab) ? selectedTab : 0
        self.onPreview = onPreview
        super.init(frame: NSRect(origin: .zero, size: Self.canvasSize))
        appearance = NSAppearance(named: .darkAqua)
        addSubview(header)
        tabs.frame = NSRect(x: 24, y: 133, width: 572, height: 28)
        tabs.cell = TelemetrySegmentCell()
        tabs.segmentStyle = .rounded
        tabs.segmentCount = 3
        tabs.trackingMode = .selectOne
        tabs.target = self
        tabs.action = #selector(selectPage)
        addSubview(tabs)
        page.frame = NSRect(x: 24, y: 174, width: 572, height: 252)
        addSubview(page)
        graphCaption.frame = NSRect(x: 24, y: 436, width: 572, height: 18)
        graphCaption.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        graphCaption.textColor = NSColor(rgb: 0xC6CA4C)
        addSubview(graphCaption)
        graph.frame = NSRect(x: 24, y: 461, width: 572, height: 48)
        graph.setAccessibilityElement(true)
        graph.setAccessibilityRole(.image)
        addSubview(graph)
        footer.frame = NSRect(x: 24, y: 530, width: 385, height: 18)
        footer.font = .monospacedSystemFont(ofSize: 9, weight: .regular)
        footer.textColor = .secondaryLabelColor
        addSubview(footer)
        preview.frame = NSRect(x: 446, y: 520, width: 150, height: 28)
        preview.bezelStyle = .rounded
        preview.target = self
        preview.action = #selector(previewBattery)
        addSubview(preview)
        refreshPreferences()
        rebuildPage()
    }

    required init?(coder: NSCoder) { fatalError("Programmatic telemetry view") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(rgb: 0x262425).setFill()
        dirtyRect.intersection(bounds).fill()
        NSColor(rgb: 0xE9E7E4, alpha: 0.15).setStroke()
        let lines = NSBezierPath()
        for y in [168.0, 518.0] { lines.move(to: NSPoint(x: 24, y: y)); lines.line(to: NSPoint(x: 596, y: y)) }
        lines.lineWidth = 1
        lines.stroke()
    }

    func update(_ snapshot: TelemetrySnapshot) {
        self.snapshot = snapshot
        header.snapshot = snapshot.battery
        header.needsDisplay = true
        if let lastTime = history.last?.time, snapshot.sampledAt < lastTime { history.removeAll(keepingCapacity: true) }
        if snapshot.sampledAt.isFinite, history.last?.time != snapshot.sampledAt {
            history.append(TelemetryGraphPoint(time: snapshot.sampledAt,
                power: settings.value.powerTelemetryEnabled ? snapshot.power?.batteryWatts : nil,
                cpu: settings.value.computeTelemetryEnabled ? snapshot.compute?.cpuFraction : nil,
                thermal: settings.value.thermalTelemetryEnabled ? thermalNumber(snapshot.thermal) : nil))
            if history.count > 300 { history.removeFirst(history.count - 300) }
        }
        refreshValues()
    }

    func refreshPreferences() {
        let languageChanged = renderedChinese != settings.chinese
        renderedChinese = settings.chinese
        header.preferences = settings.value
        header.chinese = settings.chinese
        header.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if headerTimerActive && header.reduceMotion && header.elapsed >= 0.15 { stopHeaderAnimation() }
        header.needsDisplay = true
        tabs.setAccessibilityLabel(t("遥测分类", "Telemetry pages"))
        for (i, title) in ["POWER", "COMPUTE", "THERMAL"].enumerated() {
            tabs.setLabel(title, forSegment: i)
            tabs.setWidth((tabs.frame.width - 2) / 3, forSegment: i)
        }
        preview.title = t("预览本机电量", "Preview Battery")
        preview.setAccessibilityLabel(preview.title)
        if languageChanged { rebuildPage() } else { refreshValues() }
    }

    func startHeaderAnimation() {
        stopHeaderAnimation(settle: false)
        header.elapsed = 0
        headerStart = ProcessInfo.processInfo.systemUptime
        header.needsDisplay = true
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            if let window = self.window, !window.isVisible { self.stopHeaderAnimation(); return }
            let end = self.header.reduceMotion ? 0.15 : 2.52
            self.header.elapsed = min(end, ProcessInfo.processInfo.systemUptime - self.headerStart)
            self.header.needsDisplay = true
            if self.header.elapsed >= end { self.stopHeaderAnimation() }
        }
        timer.tolerance = 0.002
        headerTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopHeaderAnimation(settle: Bool = true) {
        headerTimer?.invalidate()
        headerTimer = nil
        if settle { header.elapsed = header.reduceMotion ? 0.15 : 2.52; header.needsDisplay = true }
    }

    /// Uses HUDView's bitmap caching path, and restores live page/timeline state after export.
    func renderPNG(at url: URL, tab: Int? = nil, seconds: Double = 2.52, demo: Bool = false) throws {
        let originalTab = selectedTab, originalElapsed = header.elapsed, originalDemo = self.demo
        defer {
            selectedTab = originalTab
            header.elapsed = originalElapsed
            self.demo = originalDemo
            refreshValues()
            header.needsDisplay = true
        }
        if let tab { selectedTab = tab }
        header.elapsed = seconds.isFinite ? max(0, seconds) : (header.reduceMotion ? 0.15 : 2.52)
        self.demo = demo
        refreshValues()
        header.needsDisplay = true
        layoutSubtreeIfNeeded()
        displayIfNeeded()
        guard let bitmap = bitmapImageRepForCachingDisplay(in: bounds),
              let png = encodePNG(bitmap) else {
            throw NSError(domain: "EndfieldCharge", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Cannot encode telemetry bitmap"])
        }
        try png.write(to: url)
    }

    private func encodePNG(_ bitmap: NSBitmapImageRep) -> Data? {
        cacheDisplay(in: bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
    }

    private func t(_ zh: String, _ en: String) -> String { settings.text(zh, en) }
    @objc private func selectPage(_ sender: NSSegmentedControl) { selectedTab = sender.selectedSegment }
    @objc private func previewBattery(_ sender: NSButton) { onPreview() }

    private func rebuildPage() {
        page.subviews.forEach { $0.removeFromSuperview() }
        rows.removeAll(keepingCapacity: true)
        tabs.selectedSegment = selectedTab
        status.frame = NSRect(x: 0, y: 0, width: 572, height: 28)
        status.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        status.textColor = .secondaryLabelColor
        page.addSubview(status)
        let names: [String]
        switch selectedTab {
        case 1: names = [t("CPU 使用率", "CPU usage"), t("内存使用（估算）", "Memory used (approx.)"),
            t("压缩内存", "Compressed memory"), "Swap", t("内存压力", "Memory pressure")]
        case 2: names = [t("系统热状态", "System thermal state"), t("正常", "Nominal"), t("稍热", "Fair"),
            t("严重", "Serious"), t("临界", "Critical")]
        default: names = [t("电池能量（估算）", "Battery energy (approx.)"), t("电量", "Battery level"),
            t("电池侧功率（估算）", "Battery-side power (approx.)"), t("适配器报告功率", "Adapter-reported power"),
            t("循环次数", "Cycle count"), t("近期平均放电（估算）", "Recent discharge (approx.)")]
        }
        for (index, name) in names.enumerated() {
            let y = CGFloat(36 + index * 36)
            let label = NSTextField(labelWithString: name)
            label.frame = NSRect(x: 0, y: y, width: 330, height: 22)
            label.font = .systemFont(ofSize: 12)
            label.textColor = NSColor(rgb: 0xE9E7E4)
            let value = NSTextField(labelWithString: "—")
            value.frame = NSRect(x: 330, y: y, width: 242, height: 22)
            value.alignment = .right
            value.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            value.textColor = .white
            page.addSubview(label); page.addSubview(value)
            let line = NSBox(frame: NSRect(x: 0, y: y + 28, width: 572, height: 1))
            line.boxType = .separator
            page.addSubview(line)
            rows.append((label, value))
        }
        refreshValues()
    }

    private func refreshValues() {
        let enabled: Bool
        let values: [String]
        switch selectedTab {
        case 1:
            enabled = settings.value.computeTelemetryEnabled
            let c = snapshot?.compute
            values = [c?.cpuFraction.flatMap { $0.isFinite ? String(format: "%.1f %%", $0 * 100) : nil } ?? "—",
                c?.memoryUsedBytes.map { "≈" + bytes($0) + " / " + bytes(c?.memoryTotalBytes ?? 0) } ?? "—",
                c?.compressedBytes.map(bytes) ?? "—", c?.swapUsedBytes.map(bytes) ?? "—", pressureText(c?.pressure)]
            graph.values = enabled ? history.map(\.cpu) : []
            graph.fixedRange = 0...1
            graphCaption.stringValue = t("/// 近期 CPU 使用率", "/// RECENT CPU USAGE")
            status.stringValue = t("/// 内存估算 = 活跃 + 不可换出 + 压缩", "/// MEMORY ESTIMATE = ACTIVE + WIRED + COMPRESSED")
        case 2:
            enabled = settings.value.thermalTelemetryEnabled
            let thermal = snapshot?.thermal
            values = [thermalText(thermal), t("系统运行正常", "Normal operation"), t("系统轻度升温", "Mild thermal load"),
                t("系统限制性能", "Performance constrained"), t("热负载达到临界", "Critical thermal load")]
            graph.values = enabled ? history.map(\.thermal) : []
            graph.fixedRange = 0...3
            graphCaption.stringValue = t("/// 近期系统热状态", "/// RECENT SYSTEM THERMAL STATE")
            status.stringValue = t("/// 系统公开状态 · 不代表实测温度", "/// PUBLIC SYSTEM STATE · NO MEASURED TEMPERATURE")
        default:
            enabled = settings.value.powerTelemetryEnabled
            let b = snapshot?.battery, p = snapshot?.power
            values = [b?.energyWh.map { String(format: "≈%.1f Wh", $0) } ?? "—",
                b?.percent.map { "\($0) %" } ?? "—", watts(p?.batteryWatts, signed: true),
                p?.adapterWatts.map { "\($0) W" } ?? "—", p?.cycleCount.map(String.init) ?? "—", watts(p?.averageDischargeWatts)]
            graph.values = enabled ? history.map(\.power) : []
            graph.fixedRange = nil
            graphCaption.stringValue = t("/// 近期电池侧功率", "/// RECENT BATTERY-SIDE POWER")
            status.stringValue = t("/// 电池侧 + 充电 / − 放电 · 与适配器功率不同", "/// BATTERY + CHARGING / − DISCHARGING · ADAPTER IS SEPARATE")
        }
        graph.times = enabled ? history.map(\.time) : []
        for (index, row) in rows.enumerated() {
            row.value.stringValue = enabled ? values[index] : "—"
            row.value.textColor = selectedTab == 2 && index == 0 && enabled
                && (snapshot?.thermal == .serious || snapshot?.thermal == .critical) ? NSColor(rgb: 0xFF4D4F) : .white
            row.value.setAccessibilityLabel(row.label.stringValue + ": " + row.value.stringValue)
        }
        if !enabled { status.stringValue = t("/// 此模块已停用 · 可在设置中启用", "/// MODULE DISABLED · ENABLE IN SETTINGS") }
        graph.alert = selectedTab == 2 && (snapshot?.thermal == .serious || snapshot?.thermal == .critical)
        graph.setAccessibilityLabel(graphCaption.stringValue + " · " + t("最多 300 个采样", "Up to 300 samples"))
        graph.needsDisplay = true
        footer.stringValue = demo ? t("/// 演示数据 · 非本机读数", "/// DEMO FIXTURE · NOT LIVE READINGS")
            : t("/// 本机采样 · — 表示暂不可用", "/// LOCAL SAMPLE · — MEANS UNAVAILABLE")
    }

    private func watts(_ value: Double?, signed: Bool = false) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: signed ? "≈%+.1f W" : "≈%.1f W", value)
    }
    private func bytes(_ value: UInt64) -> String { String(format: "%.2f GiB", Double(value) / 1_073_741_824) }
    private func pressureText(_ pressure: MemoryPressureLevel?) -> String {
        switch pressure {
        case .normal: return t("正常", "Normal")
        case .warning: return t("警告", "Warning")
        case .critical: return t("临界", "Critical")
        default: return "—"
        }
    }
    private func thermalText(_ thermal: ThermalLevel?) -> String {
        switch thermal {
        case .nominal: return t("正常", "Nominal")
        case .fair: return t("稍热", "Fair")
        case .serious: return t("严重", "Serious")
        case .critical: return t("临界", "Critical")
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
    deinit { headerTimer?.invalidate() }
}
