import AppKit
import ChargeCore

extension SettingsWindowController {
    func editPlayback(_ update: (inout CapsulePlayback) -> Void) {
        var value = settings.value
        update(&value.playback)
        value.normalizeTelemetryConfiguration()
        settings.value = value
    }

    func playbackEditor(in page: NSView, y: CGFloat) {
        separator(in: page, y: y)
        place(label(t("播放队列", "Playback queue"), weight: .semibold), in: page, y: y + 15, width: 350)
        let playback = settings.value.playback
        let profiles = settings.value.capsuleProfiles
        let queue = playback.profileIDs
        selectedPlaybackIndex = min(max(0, selectedPlaybackIndex), max(0, queue.count - 1))
        let index = selectedPlaybackIndex
        let queueChoice = choice(t("顺序", "Order"), id: "playback.queue", choices: queue.isEmpty ? [t("空队列：使用当前胶囊", "Empty: use active capsule")] : queue.enumerated().map { i, id in
            "\(i + 1). " + (profiles.first { $0.id == id }?.title ?? id)
        }, selected: index, in: page, y: y + 48) { c, item in c.selectedPlaybackIndex = item; c.buildPage() }
        queueChoice.isEnabled = !queue.isEmpty
        let available = profiles.filter { !queue.contains($0.id) }
        let addChoice = choice(t("可添加胶囊", "Available capsule"), id: "playback.available", choices: available.isEmpty ? [t("已全部添加", "All added")] : available.map(\.title), selected: 0, in: page, y: y + 86) { _,_ in }
        bindings.append { c in
            for (i, id) in queue.enumerated() where i < queueChoice.numberOfItems {
                queueChoice.item(at: i)?.title = "\(i + 1). " + (c.settings.value.capsuleProfiles.first { $0.id == id }?.title ?? id)
            }
            for (i, profile) in available.enumerated() where i < addChoice.numberOfItems {
                addChoice.item(at: i)?.title = c.settings.value.capsuleProfiles.first { $0.id == profile.id }?.title ?? profile.title
            }
        }
        addChoice.isEnabled = !available.isEmpty
        let add = button(t("添加", "Add"), in: page, y: y + 124, width: 125) { c,_ in
            let i = addChoice.indexOfSelectedItem
            guard available.indices.contains(i) else { return }
            c.editPlayback { $0.profileIDs.append(available[i].id) }
            c.selectedPlaybackIndex = queue.count; c.buildPage()
        }
        add.identifier = NSUserInterfaceItemIdentifier("playback.add"); add.isEnabled = !available.isEmpty
        let remove = button(t("删除", "Delete"), in: page, x: 135, y: y + 124, width: 125) { c,_ in
            guard queue.indices.contains(index) else { return }
            c.editPlayback { $0.profileIDs.remove(at: index) }; c.buildPage()
        }
        remove.identifier = NSUserInterfaceItemIdentifier("playback.delete"); remove.isEnabled = !queue.isEmpty
        for (offset,title,delta,name) in [(0,t("上移", "Up"),-1,"up"),(1,t("下移", "Down"),1,"down")] {
            let b = button(title, in: page, x: 280 + CGFloat(offset) * 135, y: y + 124, width: 125) { c,_ in
                c.editPlayback { $0.profileIDs.swapAt(index, index + delta) }
                c.selectedPlaybackIndex += delta; c.buildPage()
            }
            b.identifier = NSUserInterfaceItemIdentifier("playback." + name); b.isEnabled = queue.indices.contains(index + delta)
        }
        let rotation = NSButton(checkboxWithTitle: t("启用队列轮播（默认关闭）", "Rotate queue (off by default)"), target: nil, action: nil)
        rotation.identifier = NSUserInterfaceItemIdentifier("playback.rotation")
        rotation.state = playback.rotationEnabled ? .on : .off; rotation.isEnabled = !queue.isEmpty
        place(rotation, in: page, y: y + 164, width: 545)
        bind(rotation) { c, sender in c.editPlayback { $0.rotationEnabled = (sender as! NSButton).state == .on }; c.buildPage() }
        textField(t("间隔 · 秒（10–600）", "Interval · seconds (10–600)"), key: "playback.interval", in: page, y: y + 202,
            value: { SettingsNumeric.text($0.settings.value.playback.intervalSeconds) }) { c,text in
                guard let value = SettingsNumeric.parse(text, range: 10...600) else { return false }
                c.editPlayback { $0.intervalSeconds = value }; return true
            }
        _ = caption(t("最多 12 项且不重复。空队列使用当前胶囊；单项不启动轮播计时器。常驻可在“显示”页开启。", "Up to 12 unique entries. Empty uses the active capsule; a single entry needs no rotation timer. Enable persistent display in Display."), in: page, y: y + 243)
        _ = caption(t("快捷键先显示当前胶囊，再播放一轮队列。常驻模式下临时预览后恢复；菜单栏可隐藏/恢复。编辑器预览只显示一项。", "Shortcut starts with the active capsule, then plays one queue round. Persistent mode resumes after preview; hide/resume from the menu bar. Editor preview shows one item."), in: page, y: y + 288)
    }
}
