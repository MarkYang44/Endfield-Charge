import AppKit
import ChargeCore

extension SettingsWindowController {
    func editProfile(_ id: String, _ update: (inout CapsuleProfile) -> Void) {
        guard let index = settings.value.capsuleProfiles.firstIndex(where: { $0.id == id }) else { return }
        var value = settings.value
        update(&value.capsuleProfiles[index])
        value.normalizeTelemetryConfiguration()
        settings.value = value
    }

    func capsulesPage(_ container: NSView) {
        let page = editorPage(in: container, height: 425)
        let profiles = settings.value.capsuleProfiles
        let id = profiles.first(where: { $0.id == settings.value.selectedCapsuleID })?.id ?? CapsuleProfile.batteryID
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        let selector = NSPopUpButton(frame: .zero, pullsDown: false)
        for profile in profiles {
            selector.addItem(withTitle: profile.title + (profile.id.hasPrefix("builtin.") ? " · " + t("内置", "Built-in") : ""))
            selector.lastItem?.representedObject = profile.id
        }
        bindings.append { c in
            for (index, profile) in c.settings.value.capsuleProfiles.enumerated() where index < selector.numberOfItems {
                selector.item(at: index)?.title = profile.title + (profile.id.hasPrefix("builtin.") ? " · " + c.t("内置", "Built-in") : "")
            }
        }
        selector.selectItem(at: profiles.firstIndex(where: { $0.id == id }) ?? 0)
        selector.setAccessibilityLabel(t("当前胶囊", "Active capsule"))
        place(selector, in: page, y: 0, width: 545, height: 28)
        bind(selector) { c, sender in
            c.commitEditing()
            if let id = (sender as! NSPopUpButton).selectedItem?.representedObject as? String {
                c.settings.value.selectedCapsuleID = id
            }
            c.buildPage()
        }
        let add = button(t("新建", "Add"), in: page, y: 38, width: 88) { c, _ in
            c.commitEditing()
            guard c.settings.value.capsuleProfiles.count < 12 else { return }
            let profile = CapsuleProfile.custom()
            c.settings.value.capsuleProfiles.append(profile)
            c.settings.value.selectedCapsuleID = profile.id
            c.buildPage()
        }
        let duplicate = button(t("复制", "Duplicate"), in: page, x: 96, y: 38, width: 100) { c, _ in
            c.commitEditing()
            guard c.settings.value.capsuleProfiles.count < 12,
                  var copy = c.settings.value.capsuleProfiles.first(where: { $0.id == id }) else { return }
            copy.id = UUID().uuidString
            copy.title = String((copy.title + c.t(" 副本", " COPY")).prefix(32))
            c.settings.value.capsuleProfiles.append(copy)
            c.settings.value.selectedCapsuleID = copy.id
            c.buildPage()
        }
        add.isEnabled = profiles.count < 12; duplicate.isEnabled = profiles.count < 12
        let delete = button(t("删除", "Delete"), in: page, x: 204, y: 38, width: 88) { c, _ in
            c.commitEditing()
            c.settings.value.capsuleProfiles.removeAll { $0.id == id && !$0.id.hasPrefix("builtin.") }
            c.settings.value.selectedCapsuleID = CapsuleProfile.batteryID
            c.draftText = c.draftText.filter { !$0.key.hasPrefix("profile.\(id).") }
            c.buildPage()
        }
        delete.isEnabled = !id.hasPrefix("builtin.")
        button(t("恢复内置", "Restore Built-ins"), in: page, x: 303, y: 38, width: 242) { c, _ in
            c.commitEditing()
            let custom = c.settings.value.capsuleProfiles.filter { !$0.id.hasPrefix("builtin.") }
            let restoredPrefixes = CapsuleProfile.defaults.map { "profile.\($0.id)." }
            c.draftText = c.draftText.filter { key, _ in !restoredPrefixes.contains { key.hasPrefix($0) } }
            c.settings.value.capsuleProfiles = CapsuleProfile.defaults + custom.prefix(7)
            c.settings.value.normalizeTelemetryConfiguration()
            c.buildPage()
        }
        textField(t("标题（1–32 字）", "Title (1–32 characters)"), key: "profile.\(id).title", in: page, y: 83,
            value: { c in c.settings.value.capsuleProfiles.first { $0.id == id }?.title ?? "" }) { c, text in
                let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty, title.count <= 32 else { return false }
                c.editProfile(id) { $0.title = title }; return true
            }
        metricPopup(t("主数值", "Primary metric"), metric: profile.primaryMetric, optional: false, in: page, y: 121) { c, metric in
            if let metric { c.editProfile(id) { $0.primaryMetric = metric } }
        }
        metricPopup(t("副数值", "Secondary metric"), metric: profile.secondaryMetric, optional: true, in: page, y: 159) { c, metric in
            c.editProfile(id) { $0.secondaryMetric = metric }
        }
        metricPopup(t("环形指标", "Ring metric"), metric: profile.ringMetric, optional: true, in: page, y: 197) { c, metric in
            c.editProfile(id) { p in
                p.ringMetric = metric
                if let metric { p.referenceMaximum = SettingsNumeric.defaultMaximum(metric) }
            }
            c.draftText.removeValue(forKey: "profile.\(id).maximum")
        }
        if let metric = profile.ringMetric {
            textField(t("环形满值", "Ring maximum") + " · " + TelemetryFormatting.unit(metric), key: "profile.\(id).maximum", in: page, y: 235,
                value: { c in SettingsNumeric.text(c.settings.value.capsuleProfiles.first { $0.id == id }?.referenceMaximum ?? 100, metric: metric) }) { c, text in
                    guard let base = SettingsNumeric.parse(text, metric: metric, positive: true) else { return false }
                    c.editProfile(id) { $0.referenceMaximum = base }; return true
                }
        }
        button(t("预览当前胶囊", "Preview Active Capsule"), in: page, y: 276, width: 240) { c, _ in
            c.commitEditing()
            c.settings.value.normalizeTelemetryConfiguration()
            c.onCapsulePreview?(id)
        }
        place(label("\(profiles.count) / 12", size: 11, mono: true), in: page, x: 475, y: 281, width: 70)
        let metrics = [profile.primaryMetric] + [profile.secondaryMetric, profile.ringMetric].compactMap { $0 }
        let unavailableMetric = metrics.first { !metricEnabled($0) } ?? profile.primaryMetric
        _ = caption(metricAvailability(unavailableMetric), in: page, y: 317)
        _ = caption(t("内置 ID 固定；恢复可找回原始电池样式。数值以本机读数为准。", "Built-in IDs stay stable. Restore recovers the original battery style. Values use local readings."), in: page, y: 355)
        editorValidation(in: page, y: 390)
    }
}
