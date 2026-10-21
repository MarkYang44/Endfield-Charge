import AppKit
import ChargeCore

extension SettingsWindowController {
    func editRule(_ id: String, _ update: (inout TelemetryAlertRule) -> Void) {
        guard let index = settings.value.telemetryAlertRules.firstIndex(where: { $0.id == id }) else { return }
        var value = settings.value
        update(&value.telemetryAlertRules[index])
        value.normalizeTelemetryConfiguration()
        settings.value = value
    }
    func rulesPage(_ container: NSView) {
        let page = editorPage(in: container, height: 555)
        let rules = settings.value.telemetryAlertRules
        let id = rules.first(where: { $0.id == selectedRuleID })?.id ?? rules.first?.id
        selectedRuleID = id
        let selector = NSPopUpButton(frame: .zero, pullsDown: false)
        if rules.isEmpty { selector.addItem(withTitle: t("暂无规则", "No rules yet")); selector.isEnabled = false }
        for rule in rules {
            selector.addItem(withTitle: (rule.enabled ? "● " : "○ ") + rule.name)
            selector.lastItem?.representedObject = rule.id
        }
        if let index = rules.firstIndex(where: { $0.id == id }) { selector.selectItem(at: index) }
        bindings.append { c in
            for (index, rule) in c.settings.value.telemetryAlertRules.enumerated() where index < selector.numberOfItems {
                selector.item(at: index)?.title = (rule.enabled ? "● " : "○ ") + rule.name
            }
        }
        selector.setAccessibilityLabel(t("提醒规则", "Alert rules"))
        place(selector, in: page, y: 0, width: 350, height: 28)
        bind(selector) { c, sender in
            c.commitEditing()
            c.selectedRuleID = (sender as! NSPopUpButton).selectedItem?.representedObject as? String
            c.buildPage()
        }
        let add = button(t("新建", "Add"), in: page, x: 362, y: 0, width: 88) { c, _ in
            c.commitEditing()
            guard c.settings.value.telemetryAlertRules.count < 16 else { return }
            let rule = TelemetryAlertRule.custom()
            c.settings.value.telemetryAlertRules.append(rule)
            c.selectedRuleID = rule.id
            c.buildPage()
        }
        add.isEnabled = rules.count < 16
        let delete = button(t("删除", "Delete"), in: page, x: 458, y: 0, width: 87) { c, _ in
            c.commitEditing()
            c.settings.value.telemetryAlertRules.removeAll { $0.id == id }
            if let id { c.draftText = c.draftText.filter { !$0.key.hasPrefix("rule.\(id).") } }
            c.selectedRuleID = nil
            c.buildPage()
        }
        delete.isEnabled = id != nil
        guard let id, let rule = rules.first(where: { $0.id == id }) else {
            _ = caption(t("最多 16 条本机规则，新规则默认关闭。点击“新建”开始配置。", "Up to 16 local rules. New rules start disabled. Click Add to configure one."), in: page, y: 55)
            ruleExplanation(in: page, y: 120)
            return
        }
        let enabled = NSButton(checkboxWithTitle: t("启用此规则", "Enable this rule"), target: nil, action: nil)
        place(enabled, in: page, y: 39, width: 350)
        bind(enabled) { c, sender in c.editRule(id) { $0.enabled = (sender as! NSButton).state == .on } }
        bindings.append { c in enabled.state = c.settings.value.telemetryAlertRules.first { $0.id == id }?.enabled == true ? .on : .off }
        textField(t("名称（1–32 字）", "Name (1–32 characters)"), key: "rule.\(id).name", in: page, y: 77,
            value: { c in c.settings.value.telemetryAlertRules.first { $0.id == id }?.name ?? "" }) { c, text in
                guard let name = ConfigurationTextLimit.name.accepted(text) else { return false }
                c.editRule(id) { $0.name = name }; return true
            }
        choice(t("触发类型", "Trigger type"), id: "rule.kind", choices: [t("数值阈值", "Numeric threshold"),t("状态变化", "State change")], selected: rule.condition == .threshold ? 0 : 1, in: page, y: 115) { c,item in
            c.commitEditing()
            c.editRule(id) { $0.condition = item == 0 ? .threshold : .stateChange; if $0.condition == .stateChange && $0.source == nil { $0.source = .thermal } }
            c.buildPage()
        }
        if rule.condition == .threshold {
            metricPopup(t("指标", "Metric"), metric: rule.metric, optional: false, in: page, y: 153) { c, metric in
                if let metric {
                    c.editRule(id) { $0.metric = metric; $0.threshold = SettingsNumeric.defaultMaximum(metric) * 0.9 }
                    c.draftText.removeValue(forKey: "rule.\(id).threshold")
                }
            }
            place(label(t("严格比较", "Strict comparison")), in: page, y: 195, width: 260)
            let comparison = NSSegmentedControl(labels: [t("大于 >", "Above >"), t("小于 <", "Below <")], trackingMode: .selectOne, target: nil, action: nil)
            comparison.selectedSegment = rule.comparison == .above ? 0 : 1
            comparison.setAccessibilityLabel(t("严格比较", "Strict comparison"))
            place(comparison, in: page, x: 270, y: 191, width: 275, height: 28)
            bind(comparison) { c, sender in c.editRule(id) { $0.comparison = (sender as! NSSegmentedControl).selectedSegment == 0 ? .above : .below } }
            textField(t("阈值", "Threshold") + " · " + TelemetryFormatting.unit(rule.metric), key: "rule.\(id).threshold", in: page, y: 229,
                value: { c in SettingsNumeric.text(c.settings.value.telemetryAlertRules.first { $0.id == id }?.threshold ?? 0, metric: rule.metric) }) { c, text in
                    guard let base = SettingsNumeric.parse(text, metric: rule.metric) else { return false }
                    c.editRule(id) { $0.threshold = base }; return true
                }
        } else {
            let source = rule.source ?? .thermal
            choice(t("状态来源", "State source"), id: "rule.source", choices: [t("系统散热", "System thermal"),t("内存压力", "Memory pressure")], selected: source == .thermal ? 0 : 1, in: page, y: 153) { c,item in
                c.commitEditing()
                c.editRule(id) { $0.source = item == 0 ? .thermal : .memoryPressure; $0.targetState = nil }
                c.buildPage()
            }
            let states: [TelemetryState] = source == .thermal ? [.thermal(.nominal),.thermal(.fair),.thermal(.serious),.thermal(.critical)] : [.memoryPressure(.normal),.memoryPressure(.warning),.memoryPressure(.critical)]
            let titles = source == .thermal ? [t("正常", "Nominal"),t("轻度", "Fair"),t("严重", "Serious"),t("危急", "Critical")] : [t("正常", "Normal"),t("警告", "Warning"),t("危急", "Critical")]
            choice(t("目标状态", "Target state"), id: "rule.target", choices: [t("任何变化", "Any change")] + titles, selected: rule.targetState.flatMap { states.firstIndex(of: $0).map { $0 + 1 } } ?? 0, in: page, y: 191) { c,item in
                c.editRule(id) { $0.targetState = item == 0 ? nil : states[item - 1] }
            }
            _ = caption(t("仅已知状态变化可触发；未知读数不建立状态。切换来源会清空目标。", "Only known transitions can trigger. Unknown readings establish no state. Changing source clears the target."), in: page, y: 229)
        }
        textField(t("持续时间 · 秒（0–300）", "Hold · seconds (0–300)"), key: "rule.\(id).hold", in: page, y: 267,
            value: { c in SettingsNumeric.text(c.settings.value.telemetryAlertRules.first { $0.id == id }?.holdSeconds ?? 0) }) { c, text in
                guard let value = SettingsNumeric.parse(text, range: 0...300) else { return false }
                c.editRule(id) { $0.holdSeconds = value }; return true
            }
        textField(t("冷却 · 秒（10–86400）", "Cooldown · seconds (10–86400)"), key: "rule.\(id).cooldown", in: page, y: 305,
            value: { c in SettingsNumeric.text(c.settings.value.telemetryAlertRules.first { $0.id == id }?.cooldownSeconds ?? 30) }) { c, text in
                guard let value = SettingsNumeric.parse(text, range: 10...86400) else { return false }
                c.editRule(id) { $0.cooldownSeconds = value }; return true
            }
        _ = caption(rule.condition == .threshold ? metricAvailability(rule.metric) : t("首次采样仅建立基线。冷却期内变化会被消耗，不会稍后重播。", "First sample establishes a baseline. Transitions during cooldown are consumed, never replayed later."), in: page, y: 345)
        ruleExplanation(in: page, y: 385, stateChange: rule.condition == .stateChange)
        editorValidation(in: page, y: 500)
    }
    private func ruleExplanation(in page: NSView, y: CGFloat, stateChange: Bool = false) {
        let message = NSTextField(wrappingLabelWithString: stateChange ? t(
            "首次已知读数仅建立基线；状态需保持所设持续时间。冷却期内变化不会稍后重播。后台每 30 秒检查，可能跳过短暂变化。停用来源模块不强制采集。散热已有默认提醒，请按需启用自定义规则。",
            "First known reading establishes a baseline. A changed state must last for the hold time. Cooldown transitions are never replayed. Background checks run every 30 s and can miss brief changes. Disabled sources stay unavailable. Built-in thermal alerts already exist; enable custom rules as needed.") : t(
            "首次采样只建立基线，不重播启动前提醒。触发后需先恢复正常才重新布防；后台每 30 秒检查，短暂越界可能被跳过。停用模块不强制采集。电池/散热已有默认提醒，仅按需要启用自定义规则。",
            "First sample establishes a baseline; no startup replay. Recover to rearm after firing. Background checks run every 30 s and can miss brief crossings. Disabled modules stay unavailable. Built-in battery/thermal alerts already exist; enable custom rules only as needed."))
        message.font = .systemFont(ofSize: 11)
        message.textColor = .secondaryLabelColor
        place(message, in: page, y: y, width: 545, height: 94)
    }
}
