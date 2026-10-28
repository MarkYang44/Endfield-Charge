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
        let page = editorPage(in: container, height: 1220)
        let profiles = settings.value.capsuleProfiles
        let id = profiles.first(where: { $0.id == settings.value.selectedCapsuleID })?.id ?? CapsuleProfile.batteryID
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        let selector = NSPopUpButton(frame: .zero, pullsDown: false)
        for profile in profiles {
            selector.addItem(withTitle: profile.title + (profile.id.hasPrefix("builtin.") ? " · " + t("内置", "Built-in") : ""))
            selector.lastItem?.representedObject = profile.id
        }
        selector.menu?.autoenablesItems = false
        selector.menu?.addItem(.separator())
        for metric: TelemetryMetric in [.codexFiveHourRemainingPercent, .codexWeeklyRemainingPercent] {
            let item = NSMenuItem(title: metric == .codexFiveHourRemainingPercent ? t("Codex · 5小时", "Codex · 5 hours") : t("Codex · 每周", "Codex · Weekly"), action: nil, keyEquivalent: "")
            item.representedObject = metric
            selector.menu?.addItem(item)
        }
        bindings.append { c in
            let current = c.settings.value.capsuleProfiles
            for item in selector.itemArray {
                if let metric = item.representedObject as? TelemetryMetric {
                    item.isEnabled = current.contains { $0.id == "preset." + metric.rawValue }
                        || current.count < ConfigurationLimits.maximumProfiles
                } else if let id = item.representedObject as? String, let profile = current.first(where: { $0.id == id }) {
                    item.title = profile.title + (id.hasPrefix("builtin.") ? " · " + c.t("内置", "Built-in") : "")
                }
            }
        }
        selector.selectItem(at: profiles.firstIndex(where: { $0.id == id }) ?? 0)
        selector.setAccessibilityLabel(t("当前胶囊", "Active capsule"))
        place(selector, in: page, y: 0, width: 545, height: 28)
        bind(selector) { c, sender in
            guard c.appearanceMutationAllowed() else {
                selector.selectItem(at: profiles.firstIndex(where: { $0.id == id }) ?? 0)
                return
            }
            let choice = (sender as! NSPopUpButton).selectedItem?.representedObject
            if let metric = choice as? TelemetryMetric {
                var value = c.settings.value
                if value.selectCodexQuotaPreset(metric) != nil { c.settings.value = value }
            } else if let id = choice as? String {
                c.settings.value.selectedCapsuleID = id
            }
            c.buildPage()
        }
        let add = button(t("新建", "Add"), in: page, y: 38, width: 88) { c, _ in
            guard c.appearanceMutationAllowed() else { return }
            guard c.settings.value.capsuleProfiles.count < ConfigurationLimits.maximumProfiles else { return }
            let profile = CapsuleProfile.custom()
            c.settings.value.capsuleProfiles.append(profile)
            c.settings.value.selectedCapsuleID = profile.id
            c.buildPage()
        }
        let duplicate = button(t("复制", "Duplicate"), in: page, x: 96, y: 38, width: 100) { c, _ in
            guard c.appearanceMutationAllowed() else { return }
            guard c.settings.value.capsuleProfiles.count < ConfigurationLimits.maximumProfiles,
                  var copy = c.settings.value.capsuleProfiles.first(where: { $0.id == id }) else { return }
            copy.id = UUID().uuidString
            copy.title = ConfigurationTextLimit.name.bounded(copy.title + c.t(" 副本", " COPY"))
            c.settings.value.capsuleProfiles.append(copy)
            c.settings.value.selectedCapsuleID = copy.id
            c.buildPage()
        }
        add.isEnabled = profiles.count < ConfigurationLimits.maximumProfiles; duplicate.isEnabled = profiles.count < ConfigurationLimits.maximumProfiles
        let delete = button(t("删除", "Delete"), in: page, x: 204, y: 38, width: 88) { c, _ in
            guard c.appearanceMutationAllowed() else { return }
            var value = c.settings.value
            value.capsuleProfiles.removeAll { $0.id == id && !$0.id.hasPrefix("builtin.") }
            value.selectedCapsuleID = CapsuleProfile.batteryID
            value.normalizeTelemetryConfiguration()
            c.settings.value = value
            c.draftText = c.draftText.filter { !$0.key.hasPrefix("profile.\(id).") }
            c.buildPage()
        }
        delete.isEnabled = !id.hasPrefix("builtin.")
        button(t("恢复内置", "Restore Built-ins"), in: page, x: 303, y: 38, width: 242) { c, _ in
            guard c.appearanceMutationAllowed() else { return }
            let custom = c.settings.value.capsuleProfiles.filter { !$0.id.hasPrefix("builtin.") }
            let restoredPrefixes = CapsuleProfile.defaults.map { "profile.\($0.id)." }
            c.draftText = c.draftText.filter { key, _ in !restoredPrefixes.contains { key.hasPrefix($0) } }
            c.settings.value.capsuleProfiles = CapsuleProfile.defaults + custom.prefix(7)
            c.settings.value.normalizeTelemetryConfiguration()
            c.buildPage()
        }
        textField(t("标题（1–32 字）", "Title (1–32 characters)"), key: "profile.\(id).title", in: page, y: 83,
            value: { c in c.settings.value.capsuleProfiles.first { $0.id == id }?.title ?? "" }) { c, text in
                guard let title = ConfigurationTextLimit.name.accepted(text) else { return false }
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
        appearanceEditor(id, profile: profile, in: page, y: 430)
        playbackEditor(in: page, y: 800)
        button(t("分享与导入…", "Sharing & Import…"), in: page, y: 1155, width: 240) { c, _ in c.showSharing() }
    }
}
