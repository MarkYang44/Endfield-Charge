import AppKit
import ChargeCore

private final class SettingsBackground: NSView {
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(rgb: 0x262425).setFill()
        // Recent AppKit may pass dirty regions outside a subview's bounds.
        // Painting only our own rectangle prevents the footer covering the other controls.
        dirtyRect.intersection(bounds).fill()
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    let settings: AppSettings
    let onPreview: (Bool?) -> Void
    private let onClose: (Int, NSRect) -> Void
    private let onScreenChange: (() -> Void)?
    var selectedTab: Int
    var actions: [ObjectIdentifier: (SettingsWindowController, NSControl) -> Void] = [:]
    var bindings: [(SettingsWindowController) -> Void] = []
    let accent = NSColor(rgb: 0xC6CA4C)
    private let tabs = NSSegmentedControl()
    private let content = SettingsBackground(frame: NSRect(x: 0, y: 0, width: 620, height: 480))
    private var page: NSView?
    private var renderedChinese: Bool
    private var screenObserver: NSObjectProtocol?
    private static let tabsID = NSToolbarItem.Identifier("settings.tabs")

    init(settings: AppSettings, selectedTab: Int, frame: NSRect?, onPreview: @escaping (Bool?) -> Void,
         onClose: @escaping (Int, NSRect) -> Void, onScreenChange: (() -> Void)? = nil) {
        self.settings = settings
        self.selectedTab = (0..<5).contains(selectedTab) ? selectedTab : 0
        self.onPreview = onPreview
        self.onClose = onClose
        self.onScreenChange = onScreenChange
        renderedChinese = settings.chinese
        let window = NSWindow(contentRect: content.frame, styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.titleVisibility = .hidden
        window.contentView = content
        window.toolbarStyle = .unifiedCompact
        let toolbar = NSToolbar(identifier: "Endfield.Settings")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.centeredItemIdentifier = Self.tabsID
        tabs.trackingMode = .selectOne
        tabs.target = self
        tabs.action = #selector(selectTab)
        rebuild()
        window.toolbar = toolbar
        if let frame { window.setFrame(frame, display: false) } else { window.center() }
        settings.onUIChange = { [weak self] in self?.refresh() }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                guard let self, self.selectedTab == 1 else { return }
                self.buildPage()
            }
    }

    required init?(coder: NSCoder) { fatalError("Programmatic settings window") }

    func present() {
        settings.refreshLogin()
        showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        settings.onUIChange = nil
        if let window { onClose(selectedTab, window.frame) }
    }

    func windowDidChangeScreen(_ notification: Notification) { onScreenChange?() }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    func t(_ zh: String, _ en: String) -> String { settings.text(zh, en) }

    private func rebuild() {
        renderedChinese = settings.chinese
        window?.title = "Endfield Charge · " + t("设置", "Settings")
        content.subviews.forEach { $0.removeFromSuperview() }
        page = nil
        let names = [t("通用", "General"), t("显示与动画", "HUD & Animation"), t("提醒", "Alerts"), t("遥测", "Telemetry"), t("关于", "About")]
        tabs.segmentCount = names.count
        for (index, name) in names.enumerated() { tabs.setLabel(name, forSegment: index); tabs.setWidth(0, forSegment: index) }
        tabs.selectedSegment = selectedTab
        tabs.setAccessibilityLabel(t("设置分类", "Settings sections"))
        tabs.frame.size = NSSize(width: 520, height: 28)
        let bolt = NSImageView(frame: NSRect(x: 24, y: 28, width: 28, height: 32))
        bolt.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Flash")
        bolt.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 26, weight: .regular)
        bolt.contentTintColor = accent
        content.addSubview(bolt)
        let title = label("ENDFIELD CHARGE", size: 17, weight: .bold, mono: true)
        title.attributedStringValue = NSAttributedString(string: title.stringValue, attributes: [.font: title.font!, .kern: 2])
        place(title, in: content, x: 64, y: 26, width: 390, height: 24)
        let subtitle = label("/// MACOS POWER TERMINAL", size: 9, mono: true)
        subtitle.textColor = .secondaryLabelColor
        place(subtitle, in: content, x: 64, y: 53, width: 320, height: 16)
        let power = label("01 / POWER", size: 10, mono: true)
        power.textColor = accent
        place(power, in: content, x: 529, y: 40, width: 80, height: 18)
        separator(in: content, y: 84)
        buildPage()
    }

    private func buildPage() {
        page?.removeFromSuperview()
        // Bindings own only controls on the currently selected page, never a hidden page tree.
        actions.removeAll(keepingCapacity: true)
        bindings.removeAll(keepingCapacity: true)
        let page = SettingsBackground(frame: NSRect(x: 24, y: 104, width: 572, height: 310))
        self.page = page
        content.addSubview(page)
        switch selectedTab {
        case 1: animationPage(page)
        case 2: alertsPage(page)
        case 3: telemetryPage(page)
        case 4: aboutPage(page)
        default: generalPage(page)
        }
        // Footer controls are recreated with the page, so their action entries stay valid.
        content.subviews.filter { $0.identifier?.rawValue == "footer" }.forEach { $0.removeFromSuperview() }
        let footer = SettingsBackground(frame: NSRect(x: 0, y: 434, width: 620, height: 46))
        footer.identifier = NSUserInterfaceItemIdentifier("footer")
        content.addSubview(footer)
        separator(in: footer, y: 0)
        let hint = label(t("设置自动保存并即时生效", "Changes save automatically"), size: 10)
        hint.textColor = .secondaryLabelColor
        place(hint, in: footer, x: 24, y: 17, width: 350, height: 18)
        button(t("预览本机电量", "Preview Battery"), in: footer, x: 461, y: 10, width: 135) { c, _ in c.onPreview(nil) }
        refresh()
    }

    private func refresh() {
        if renderedChinese != settings.chinese { rebuild(); return }
        for update in bindings { update(self) }
    }

    @objc private func selectTab(_ sender: NSSegmentedControl) {
        selectedTab = sender.selectedSegment
        buildPage()
    }

    @objc func controlChanged(_ sender: NSControl) { actions[ObjectIdentifier(sender)]?(self, sender) }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.tabsID, .flexibleSpace]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard identifier == Self.tabsID else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.view = tabs
        return item
    }
}
