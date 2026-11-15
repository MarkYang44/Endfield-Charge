import AppKit

/// UI roles run as accessory apps, so macOS never shows their menu bar. A hidden main menu still routes
/// the standard key equivalents: ⌘Z/⌘X/⌘C/⌘V/⌘A inside fields, ⌘W/⌘M for the window and ⌘1… for sections.
/// Keyboard actions switch instantly; nothing here animates.
enum UtilityMenu {
    static func install(chinese: Bool, sections: [String], target: AnyObject, action: Selector) {
        func t(_ zh: String, _ en: String) -> String { chinese ? zh : en }
        func item(_ title: String, _ selector: Selector, _ key: String,
                  _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            return item
        }
        let main = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            entry.submenu = menu
            main.addItem(entry)
        }
        submenu("Endfield Charge", [])
        submenu(t("文件", "File"), [item(t("关闭窗口", "Close Window"), #selector(NSWindow.performClose(_:)), "w")])
        submenu(t("编辑", "Edit"), [
            item(t("撤销", "Undo"), Selector(("undo:")), "z"),
            item(t("重做", "Redo"), Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item(t("剪切", "Cut"), #selector(NSText.cut(_:)), "x"),
            item(t("拷贝", "Copy"), #selector(NSText.copy(_:)), "c"),
            item(t("粘贴", "Paste"), #selector(NSText.paste(_:)), "v"),
            item(t("全选", "Select All"), #selector(NSText.selectAll(_:)), "a")
        ])
        submenu(t("显示", "View"), sections.enumerated().map { index, title in
            let entry = item(title, action, String(index + 1))
            entry.target = target
            entry.tag = index
            return entry
        })
        submenu(t("窗口", "Window"), [item(t("最小化", "Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m")])
        NSApp.mainMenu = main
    }
}

extension NSWindow {
    /// Fixed-size windows restore only their saved top-left corner, so a layout change between versions
    /// never clips content. A position stranded on a disconnected display falls back to centering.
    func restoreTopLeft(from saved: NSRect?) {
        guard let saved, saved.minX.isFinite, saved.maxY.isFinite else { center(); return }
        let restored = NSRect(x: saved.minX, y: saved.maxY - frame.height, width: frame.width, height: frame.height)
        let titleBar = NSRect(x: restored.minX, y: restored.maxY - 28, width: restored.width, height: 28)
        let reachable = NSScreen.screens.contains { screen in
            let visible = screen.visibleFrame.intersection(titleBar)
            return visible.width >= 80 && visible.height > 0
        }
        if reachable { setFrame(restored, display: false) } else { center() }
    }
}
