import AppKit
import ChargeCore

extension SettingsWindowController {
    func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, mono: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = mono ? .monospacedSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
        return field
    }

    func place(_ view: NSView, in parent: NSView, x: CGFloat = 0, y: CGFloat, width: CGFloat, height: CGFloat = 24) {
        view.frame = NSRect(x: x, y: y, width: width, height: height)
        parent.addSubview(view)
    }

    func caption(_ text: String, in page: NSView, y: CGFloat, warning: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: 11)
        field.textColor = warning ? .systemOrange : .secondaryLabelColor
        place(field, in: page, y: y, width: page.bounds.width, height: 34)
        return field
    }

    func separator(in page: NSView, y: CGFloat) {
        let line = NSBox(); line.boxType = .separator
        place(line, in: page, y: y, width: page.bounds.width, height: 1)
    }

    func bind(_ control: NSControl, action: @escaping (SettingsWindowController, NSControl) -> Void) {
        control.target = self; control.action = #selector(controlChanged)
        actions[ObjectIdentifier(control)] = action
    }

    @discardableResult func button(_ title: String, in page: NSView, x: CGFloat = 0, y: CGFloat, width: CGFloat = 135,
                                  action: @escaping (SettingsWindowController, NSControl) -> Void) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        place(button, in: page, x: x, y: y, width: width, height: 28)
        bind(button, action: action)
        return button
    }

    func toggle(_ title: String, _ key: WritableKeyPath<Preferences, Bool>, in page: NSView, y: CGFloat, width: CGFloat? = nil) {
        let toggle = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        place(toggle, in: page, y: y, width: width ?? page.bounds.width)
        bind(toggle) { c, sender in c.settings.value[keyPath: key] = (sender as! NSButton).state == .on }
        bindings.append { c in toggle.state = c.settings.value[keyPath: key] ? .on : .off }
    }

    func popup(_ title: String, choices: [(String, String)], key: WritableKeyPath<Preferences, String>,
               in page: NSView, y: CGFloat, width: CGFloat = 235) {
        place(label(title), in: page, y: y + 4, width: 230)
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        for (title, value) in choices { popup.addItem(withTitle: title); popup.lastItem?.representedObject = value }
        place(popup, in: page, x: page.bounds.width - width, y: y, width: width, height: 28)
        popup.setAccessibilityLabel(title)
        bind(popup) { c, sender in
            if let value = (sender as! NSPopUpButton).selectedItem?.representedObject as? String { c.settings.value[keyPath: key] = value }
        }
        bindings.append { c in
            if let item = popup.itemArray.first(where: { $0.representedObject as? String == c.settings.value[keyPath: key] }) { popup.select(item) }
        }
    }

    func slider(_ title: String, in page: NSView, y: CGFloat, range: ClosedRange<Double>, step: Double,
                value: @escaping (Preferences) -> Double, set: @escaping (inout Preferences, Double) -> Void,
                format: @escaping (Double) -> String, enabled: ((Preferences) -> Bool)? = nil) {
        let name = label(title)
        place(name, in: page, y: y + 4, width: 280)
        let slider = NSSlider(value: 0, minValue: range.lowerBound, maxValue: range.upperBound, target: nil, action: nil)
        slider.isContinuous = true
        slider.setAccessibilityLabel(title)
        place(slider, in: page, x: 337, y: y + 2, width: 190)
        let readout = label("", size: 12, mono: true)
        readout.alignment = .right
        place(readout, in: page, x: 527, y: y + 4, width: 45)
        bind(slider) { c, sender in
            let snapped = min(range.upperBound, max(range.lowerBound, (sender.doubleValue / step).rounded() * step))
            set(&c.settings.value, snapped)
        }
        bindings.append { c in
            let v = value(c.settings.value); slider.doubleValue = v; readout.stringValue = format(v)
            // A threshold whose switch is off reads as inactive instead of silently doing nothing.
            guard let enabled else { return }
            let active = enabled(c.settings.value)
            slider.isEnabled = active && !c.configurationPending
            name.textColor = active ? .labelColor : .tertiaryLabelColor
            readout.textColor = active ? .labelColor : .tertiaryLabelColor
        }
    }

    /// Wrapping caption sized to its text, so stacked editor sections keep one rhythm; returns its bottom edge.
    @discardableResult func note(_ text: String, in page: NSView, y: CGFloat, width: CGFloat? = nil) -> CGFloat {
        let field = caption(text, in: page, y: y)
        let width = width ?? page.bounds.width
        let height = ceil(field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 10_000)).height ?? 34)
        field.frame = NSRect(x: 0, y: y, width: width, height: height)
        return y + height
    }

    /// Accent text link that jumps to a related section instead of telling people where to look.
    @discardableResult func link(_ title: String, in page: NSView, right: CGFloat, y: CGFloat, width: CGFloat = 200,
                                 action: @escaping (SettingsWindowController, NSControl) -> Void) -> NSButton {
        let link = LinkButton()
        link.cell = LinkCell(textCell: title)
        link.isBordered = false
        link.font = .systemFont(ofSize: 11, weight: .medium)
        link.alignment = .right
        link.setAccessibilityLabel(title)
        place(link, in: page, x: right - width, y: y, width: width, height: 20)
        bind(link, action: action)
        return link
    }

    /// The footer is the one always-visible status line: it confirms auto-save, or explains in orange
    /// why an input stays unsaved, wherever the edited field sits on a scrolled page.
    func updateStatusLine(_ message: String? = nil) {
        guard let status = validationMessage else { return }
        let warning = message ?? (draftText.isEmpty ? nil
            : t("有未保存的无效输入，请修正橙色字段。", "Invalid input remains unsaved; correct the orange field."))
        status.stringValue = warning ?? t("设置自动保存并即时生效", "Changes save automatically")
        status.textColor = warning == nil ? .secondaryLabelColor : .systemOrange
        status.toolTip = warning
    }
}

/// Shortcut modifiers drawn as key caps: lime when held in the combination, so the active set reads at a glance.
/// The native button keeps state, keyboard focus, tooltips and accessibility; a press darkens the cap at once.
final class KeyCapCell: NSButtonCell {
    override func drawBezel(withFrame frame: NSRect, in controlView: NSView) {
        var fill = state == .on ? NSColor(rgb: 0xC6CA4C) : NSColor(rgb: 0x454445)
        if isHighlighted { fill = fill.blended(withFraction: 0.2, of: .black) ?? fill }
        fill.withAlphaComponent(isEnabled ? 1 : 0.4).setFill()
        NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 2), xRadius: 6, yRadius: 6).fill()
    }

    override func drawTitle(_ title: NSAttributedString, withFrame frame: NSRect, in controlView: NSView) -> NSRect {
        let text = NSMutableAttributedString(attributedString: title)
        let color = state == .on ? NSColor(rgb: 0x141313) : NSColor(rgb: 0xE9E7E4)
        text.addAttribute(.foregroundColor, value: color.withAlphaComponent(isEnabled ? 1 : 0.45),
                          range: NSRange(location: 0, length: text.length))
        return super.drawTitle(text, withFrame: frame, in: controlView)
    }
}

/// Accent link text that dims while pressed; the pointing hand marks it as navigation.
final class LinkCell: NSButtonCell {
    override func drawTitle(_ title: NSAttributedString, withFrame frame: NSRect, in controlView: NSView) -> NSRect {
        let text = NSMutableAttributedString(attributedString: title)
        let alpha: CGFloat = !isEnabled ? 0.4 : isHighlighted ? 0.6 : 1
        text.addAttribute(.foregroundColor, value: NSColor(rgb: 0xC6CA4C, alpha: alpha),
                          range: NSRange(location: 0, length: text.length))
        return super.drawTitle(text, withFrame: frame, in: controlView)
    }
}

final class LinkButton: NSButton {
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

/// Human-unit parsing never uses an unchecked integer conversion.
enum SettingsNumeric {
    static func parse(_ text: String, metric: TelemetryMetric? = nil, range: ClosedRange<Double>? = nil,
                      positive: Bool = false) -> Double? {
        guard let number = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), number.isFinite,
              !positive || number > 0, range.map({ $0.contains(number) }) ?? true else { return nil }
        let base = metric.map { TelemetryFormatting.baseValue(number, metric: $0) } ?? number
        return base.isFinite ? base : nil
    }
    static func text(_ base: Double, metric: TelemetryMetric? = nil) -> String {
        String(format: "%.8g", metric.map { TelemetryFormatting.displayValue(base, metric: $0) } ?? base)
    }
    static func defaultMaximum(_ metric: TelemetryMetric) -> Double {
        switch metric {
        case .memoryUsedBytes: return 16 * 1_073_741_824
        case .storageAvailableBytes: return 100 * 1_073_741_824
        case .networkDownloadBytesPerSecond, .networkUploadBytesPerSecond: return 10 * 1_048_576
        case .batteryEnergyWh: return 60
        default: return 100
        }
    }
}

private final class SettingsScrollPage: NSView { override var isFlipped: Bool { true } }

extension SettingsWindowController {
    func editorPage(in page: NSView) -> NSView {
        let scroll = NSScrollView(frame: page.bounds)
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        // 545 pt is the field column; the remaining gutter keeps legacy scrollers clear of controls.
        let document = SettingsScrollPage(frame: NSRect(x: 0, y: 0, width: 545, height: page.bounds.height))
        scroll.documentView = document
        page.addSubview(scroll)
        return document
    }

    /// The scrollable document ends just below its last control: no blank tail, no hidden overflow.
    func finishEditorPage(_ document: NSView, bottom: CGFloat) {
        let visible = document.enclosingScrollView?.contentSize.height ?? 0
        document.setFrameSize(NSSize(width: document.frame.width, height: max(visible, ceil(bottom + 20))))
    }

    @discardableResult func textField(_ title: String, key: String, in page: NSView, y: CGFloat,
        value: @escaping (SettingsWindowController) -> String,
        save: @escaping (SettingsWindowController, String) -> Bool) -> NSTextField {
        place(label(title), in: page, y: y + 3, width: 260)
        let field = NSTextField(string: draftText[key] ?? value(self))
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.delegate = self
        if draftText[key] != nil { field.textColor = .systemOrange }
        field.identifier = NSUserInterfaceItemIdentifier(key)
        field.setAccessibilityLabel(title)
        place(field, in: page, x: 270, y: y, width: 275, height: 25)
        textEdits[ObjectIdentifier(field)] = (key, field, save)
        bindings.append { c in
            // Respect the live field editor, including marked IME text, during peer/binding refreshes.
            if field.currentEditor() == nil { field.stringValue = c.draftText[key] ?? value(c) }
        }
        return field
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              let edit = textEdits[ObjectIdentifier(field)] else { return }
        draftText[edit.key] = field.stringValue
        guard (field.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
        validate(field)
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        validate(field)
    }
    private func validate(_ field: NSTextField) {
        guard let edit = textEdits[ObjectIdentifier(field)], draftText[edit.key] != nil else { return }
        let valid = edit.save(self, field.stringValue)
        if valid { draftText.removeValue(forKey: edit.key) } else { draftText[edit.key] = field.stringValue }
        field.textColor = valid ? .labelColor : .systemOrange
        field.toolTip = valid ? nil : t("输入无效：请输入指定范围内的有限数值，名称为 1–32 字且不超过 1024 个 UTF-8 字节。", "Invalid input: use a finite value in range, or a name of 1–32 characters and at most 1024 UTF-8 bytes.")
        updateStatusLine()
    }
    func commitEditing() {
        if let editor = window?.firstResponder as? NSTextView,
           let field = editor.delegate as? NSTextField {
            let pending = editor.string
            if let edit = textEdits[ObjectIdentifier(field)], editor.hasMarkedText() || pending != field.stringValue {
                draftText[edit.key] = pending
            }
            editor.unmarkText()
            field.stringValue = pending
        }
        window?.makeFirstResponder(nil)
        // Copy first: saves synchronously refresh bindings and can notify external owners.
        for edit in Array(textEdits.values) { validate(edit.field) }
    }

    @discardableResult func choice(_ title: String, id: String, choices: [String], selected: Int,
        in page: NSView, y: CGFloat, change: @escaping (SettingsWindowController, Int) -> Void) -> NSPopUpButton {
        place(label(title), in: page, y: y + 4, width: 260)
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: choices); popup.selectItem(at: selected)
        popup.identifier = NSUserInterfaceItemIdentifier(id); popup.setAccessibilityLabel(title)
        place(popup, in: page, x: 270, y: y, width: 275, height: 28)
        bind(popup) { c, sender in change(c, (sender as! NSPopUpButton).indexOfSelectedItem) }
        return popup
    }

    func metricPopup(_ title: String, metric: TelemetryMetric?, optional: Bool, in page: NSView,
                     y: CGFloat, set: @escaping (SettingsWindowController, TelemetryMetric?) -> Void) {
        place(label(title), in: page, y: y + 4, width: 260)
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        if optional { popup.addItem(withTitle: t("无", "None")) }
        for item in TelemetryMetric.allCases {
            popup.addItem(withTitle: TelemetryFormatting.name(item, chinese: settings.chinese) + " · " + TelemetryFormatting.unit(item))
            popup.lastItem?.representedObject = item.rawValue
        }
        if let metric, let item = popup.itemArray.first(where: { $0.representedObject as? String == metric.rawValue }) { popup.select(item) }
        place(popup, in: page, x: 270, y: y, width: 275, height: 28)
        popup.setAccessibilityLabel(title)
        bind(popup) { c, sender in
            c.commitEditing()
            let raw = (sender as! NSPopUpButton).selectedItem?.representedObject as? String
            set(c, raw.flatMap(TelemetryMetric.init(rawValue:)))
            c.buildPage()
        }
    }
    func metricEnabled(_ metric: TelemetryMetric) -> Bool {
        switch metric {
        case .batteryEnergyWh, .batteryPercent, .codexFiveHourRemainingPercent, .codexWeeklyRemainingPercent: return true
        case .cpuPercent, .memoryUsedBytes, .memoryPercent: return settings.value.computeTelemetryEnabled
        case .networkDownloadBytesPerSecond, .networkUploadBytesPerSecond: return settings.value.networkTelemetryEnabled
        case .storageAvailableBytes, .storageUsedPercent: return settings.value.storageTelemetryEnabled
        }
    }
    func metricAvailability(_ metric: TelemetryMetric) -> String {
        if metric.isCodexQuota { return t("需已登录的本机 Codex CLI；显示剩余额度，约5分钟刷新。— 表示未登录或窗口不可用。", "Requires a locally signed-in Codex CLI; remaining quota refreshes about every 5 minutes. — means unavailable.") }
        return metricEnabled(metric) ? t("— 表示暂不可用；可在“遥测”页管理模块。", "— means unavailable; manage modules in Telemetry.")
            : t("所选指标模块已停用，输入不可用。请在“遥测”页启用。", "Selected metric module is disabled; input unavailable. Enable it in Telemetry.")
    }
}
