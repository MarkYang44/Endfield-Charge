import AppKit
import ChargeCore

extension SettingsWindowController {
    /// Index keys are safe because every appearance structure/selection mutation is fenced.
    func appearanceMutationAllowed() -> Bool {
        let prefix = "profile."
        let marked = textEdits.values.contains { edit in
            edit.key.hasPrefix(prefix) && edit.key.contains(".color.") &&
                (edit.field.currentEditor() as? NSTextView)?.hasMarkedText() == true
        }
        if !marked { commitEditing() }
        guard !marked && !draftText.keys.contains(where: { $0.hasPrefix(prefix) && $0.contains(".color.") }) else {
            validationMessage?.stringValue = t("先完成或修正颜色阈值，再切换、排序或删除条件。", "Finish or correct the color threshold before switching, moving or deleting conditions.")
            if let message = validationMessage { message.scrollToVisible(message.bounds) }
            return false
        }
        return true
    }

    func appearanceEditor(_ id: String, profile: CapsuleProfile, in page: NSView, y: CGFloat) {
        separator(in: page, y: y)
        place(label(t("条件配色", "Conditional colors"), weight: .semibold), in: page, y: y + 15, width: 350)
        let conditions = profile.colorConditions
        selectedColorIndex = min(max(0, selectedColorIndex), max(0, conditions.count - 1))
        let index = selectedColorIndex
        let selector = NSPopUpButton(frame: .zero, pullsDown: false)
        selector.identifier = NSUserInterfaceItemIdentifier("appearance.selector")
        selector.setAccessibilityLabel(t("配色条件顺序", "Color condition order"))
        if conditions.isEmpty { selector.addItem(withTitle: t("暂无条件", "No conditions")); selector.isEnabled = false }
        for (i, condition) in conditions.enumerated() {
            selector.addItem(withTitle: "\(i + 1). " + TelemetryFormatting.name(condition.metric, chinese: settings.chinese))
        }
        selector.selectItem(at: index)
        place(selector, in: page, y: y + 48, width: 235, height: 28)
        bind(selector) { c, sender in
            guard c.appearanceMutationAllowed() else { (sender as! NSPopUpButton).selectItem(at: index); return }
            c.selectedColorIndex = (sender as! NSPopUpButton).indexOfSelectedItem; c.buildPage()
        }
        let add = button(t("添加", "Add"), in: page, x: 243, y: y + 48, width: 70) { c,_ in
            guard c.appearanceMutationAllowed(), conditions.count < ConfigurationLimits.maximumColorConditions else { return }
            c.editProfile(id) { $0.colorConditions.append(CapsuleColorCondition(metric: .cpuPercent, comparison: .above, threshold: 90, accent: .amber)) }
            c.selectedColorIndex = conditions.count; c.buildPage()
        }
        add.identifier = NSUserInterfaceItemIdentifier("appearance.add"); add.isEnabled = conditions.count < ConfigurationLimits.maximumColorConditions
        let remove = button(t("删除", "Delete"), in: page, x: 319, y: y + 48, width: 70) { c,_ in
            guard c.appearanceMutationAllowed() else { return }
            c.editProfile(id) { $0.colorConditions.remove(at: index) }; c.buildPage()
        }
        remove.identifier = NSUserInterfaceItemIdentifier("appearance.delete"); remove.isEnabled = !conditions.isEmpty
        for (offset, title, delta, name) in [(0,t("上移", "Up"),-1,"up"),(1,t("下移", "Down"),1,"down")] {
            let b = button(title, in: page, x: 395 + CGFloat(offset) * 78, y: y + 48, width: 72) { c,_ in
                guard c.appearanceMutationAllowed() else { return }
                c.editProfile(id) { $0.colorConditions.swapAt(index, index + delta) }
                c.selectedColorIndex += delta; c.buildPage()
            }
            b.identifier = NSUserInterfaceItemIdentifier("appearance." + name)
            b.isEnabled = conditions.indices.contains(index + delta)
        }
        if conditions.indices.contains(index) {
            let condition = conditions[index]
            let metric = choice(t("指标", "Metric"), id: "appearance.metric", choices: TelemetryMetric.allCases.map {
                TelemetryFormatting.name($0, chinese: settings.chinese) + " · " + TelemetryFormatting.unit($0)
            }, selected: TelemetryMetric.allCases.firstIndex(of: condition.metric)!, in: page, y: y + 88) { c, item in
                guard c.appearanceMutationAllowed() else { c.buildPage(); return }
                let metric = TelemetryMetric.allCases[item]
                c.editProfile(id) { $0.colorConditions[index].metric = metric; $0.colorConditions[index].threshold = SettingsNumeric.defaultMaximum(metric) * 0.9 }
                c.buildPage()
            }
            metric.toolTip = metricAvailability(condition.metric)
            choice(t("严格比较", "Strict comparison"), id: "appearance.comparison", choices: [t("大于 >", "Above >"),t("小于 <", "Below <")], selected: condition.comparison == .above ? 0 : 1, in: page, y: y + 126) { c, item in
                c.editProfile(id) { $0.colorConditions[index].comparison = item == 0 ? .above : .below }
            }
            textField(t("阈值", "Threshold") + " · " + TelemetryFormatting.unit(condition.metric), key: "profile.\(id).color.\(index).threshold", in: page, y: y + 164, value: { c in
                let values = c.settings.value.capsuleProfiles.first { $0.id == id }?.colorConditions ?? []
                return SettingsNumeric.text(values.indices.contains(index) ? values[index].threshold : condition.threshold, metric: condition.metric)
            }) { c, text in
                guard let value = SettingsNumeric.parse(text, metric: condition.metric) else { return false }
                c.editProfile(id) { $0.colorConditions[index].threshold = value }; return true
            }
            choice(t("颜色", "Color"), id: "appearance.accent", choices: [t("主题", "Theme"),t("青柠", "Lime"),t("琥珀", "Amber"),t("红色", "Red")], selected: CapsuleAccent.allCases.firstIndex(of: condition.accent)!, in: page, y: y + 202) { c, item in
                c.editProfile(id) { $0.colorConditions[index].accent = CapsuleAccent.allCases[item] }
            }
        }
        _ = caption(t("最多 4 条，按顺序首个匹配生效；相等或未知读数不匹配。无匹配使用主题色。真实警报仍优先。", "Up to 4, first match wins. Equal or unknown readings never match. Otherwise use Theme. Real alerts keep priority."), in: page, y: y + 243)
        let preview = button(t("预览配色", "Preview Colors"), in: page, y: y + 286, width: 240) { c,_ in c.commitEditing(); c.onCapsulePreview?(id) }
        preview.identifier = NSUserInterfaceItemIdentifier("appearance.preview")
        editorValidation(in: page, y: y + 322)
    }
}
