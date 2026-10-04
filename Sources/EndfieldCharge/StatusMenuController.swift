import AppKit
import ChargeCore

/// Owns one menu and updates its items in place, including while the menu is open.
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let settings: AppSettings
    private let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let timeItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var labels: [(NSMenuItem, String, String)] = []
    var onRefresh: (() -> Void)?

    init(settings: AppSettings, target: AnyObject, entries: [(String, String, Selector?, String)]) {
        self.settings = settings
        super.init()
        status.button?.image = Self.statusImage()
        status.button?.imagePosition = .imageLeading
        menu.delegate = self
        menu.autoenablesItems = false
        stateItem.isEnabled = false
        timeItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(timeItem)
        for (zh, en, action, key) in entries {
            guard let action else { menu.addItem(.separator()); continue }
            let item = NSMenuItem(title: "", action: action, keyEquivalent: key)
            item.target = target
            item.isEnabled = true
            menu.addItem(item)
            labels.append((item, zh, en))
        }
        status.menu = menu
    }

    func update(_ snapshot: BatterySnapshot) {
        let title = settings.value.showPercentage ? " " + (snapshot.percent.map { "\($0)%" } ?? "—") : ""
        if status.button?.title != title { status.button?.title = title }
        status.button?.toolTip = settings.text("终末地电量终端", "Endfield Charge")
        let state: String
        if !snapshot.hasBattery { state = settings.text("未检测到内置电池", "No internal battery") }
        else if snapshot.isCharged { state = settings.text("已充满", "Fully charged") }
        else if snapshot.isCharging { state = settings.text("正在充电", "Charging") }
        else if snapshot.externalPower { state = settings.text("外部供电 · 未充电", "External power · Not charging") }
        else { state = settings.text("电池供电", "Battery power") }
        stateItem.title = "ENDFIELD / \(state)"
        timeItem.isHidden = snapshot.minutesRemaining == nil || (snapshot.minutesRemaining ?? 0) <= 0
        if let minutes = snapshot.minutesRemaining, minutes > 0 {
            let suffix = snapshot.isCharging ? settings.text("至充满", "until full") : settings.text("剩余", "remaining")
            timeItem.title = "\(minutes / 60)h \(minutes % 60)m \(suffix)"
        }
        for (item, zh, en) in labels { item.title = settings.text(zh, en) }
    }

    func menuWillOpen(_ menu: NSMenu) { onRefresh?() }

    private static func statusImage() -> NSImage {
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"), let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            return image
        }
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            NSColor.black.setFill()
            HUDView.boltPath(in: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    deinit { NSStatusBar.system.removeStatusItem(status) }
}
