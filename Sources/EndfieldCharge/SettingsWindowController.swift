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

final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSTextFieldDelegate {
    let settings: AppSettings
    let onPreview: (Bool?) -> Void
    var onConfigurationRequest: ((ConfigurationTransactionAction) throws -> Void)?
    var sharingController: SettingsSharingController?
    private(set) var configurationPending = false
    private var closeAfterConfiguration = false
    var onCapsulePreview: ((String) -> Void)?
    private let onClose: (Int, NSRect) -> Void
    private let onScreenChange: (() -> Void)?
    var selectedTab: Int
    var actions: [ObjectIdentifier: (SettingsWindowController, NSControl) -> Void] = [:]
    var bindings: [(SettingsWindowController) -> Void] = []
    let accent = NSColor(rgb: 0xC6CA4C)
    private let tabs = NSSegmentedControl()
    private let content = SettingsBackground(frame: NSRect(x: 0, y: 0, width: 620, height: 480))
    private var page: NSView?
    private var renderedTab: Int?
    var draftText: [String: String] = [:]
    var textEdits: [ObjectIdentifier: (key: String, field: NSTextField, save: (SettingsWindowController, String) -> Bool)] = [:]
    var selectedRuleID: String?
    var selectedColorIndex = 0
    var selectedPlaybackIndex = 0
    var validationMessage: NSTextField?

    /// Section offsets registered while a scrollable page is built; jump links scroll straight to them.
    var scrollAnchors: [String: CGFloat] = [:]
    private var pendingAnchor: String?
    private var sectionLabel: NSTextField?
    private var keyboardMenuInstalled = false

    private var renderedChinese: Bool
    private var screenObserver: NSObjectProtocol?
    private static let tabsID = NSToolbarItem.Identifier("settings.tabs")
    private static let sectionCodes = ["GENERAL", "DISPLAY", "ALERTS", "TELEMETRY", "CAPSULES", "RULES", "ABOUT"]

    init(settings: AppSettings, selectedTab: Int, frame: NSRect?, onPreview: @escaping (Bool?) -> Void,
         onClose: @escaping (Int, NSRect) -> Void, onScreenChange: (() -> Void)? = nil) {
        self.settings = settings
        self.selectedTab = (0..<7).contains(selectedTab) ? selectedTab : 0
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
        window.restoreTopLeft(from: frame)
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
        flashScrollableContent()
    }

    var sectionTitles: [String] {
        [t("通用", "General"), t("显示", "Display"), t("提醒", "Alerts"), t("遥测", "Telemetry"),
         t("胶囊", "Capsules"), t("规则", "Rules"), t("关于", "About")]
    }

    /// Hidden main menu for this accessory role: editing keys in fields, ⌘W/⌘M, and ⌘1–⌘7 for sections.
    func installKeyboardMenu() {
        keyboardMenuInstalled = true
        UtilityMenu.install(chinese: settings.chinese, sections: sectionTitles, target: self,
                            action: #selector(selectSection(_:)))
    }

    @objc func selectSection(_ sender: NSMenuItem) { showSection(sender.tag) }

    /// One path for toolbar clicks, ⌘-number keys and in-page jump links.
    func showSection(_ index: Int, anchor: String? = nil) {
        guard !configurationPending, (0..<7).contains(index) else { tabs.selectedSegment = selectedTab; return }
        guard index != selectedTab || anchor != nil else { return }
        commitEditing()
        selectedTab = index
        tabs.selectedSegment = index
        pendingAnchor = anchor
        buildPage()
    }

    /// Overlay scrollers stay hidden until used; flash them once when a page opens with more content below.
    private func flashScrollableContent() {
        guard window?.isVisible == true,
              let scroll = page?.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView,
              let document = scroll.documentView,
              document.frame.height > scroll.contentView.bounds.height + 1 else { return }
        scroll.flashScrollers()
    }

    func previewActiveCapsule() {
        commitEditing()
        settings.value.normalizeTelemetryConfiguration()
        let id = settings.value.capsuleProfiles.first { $0.id == settings.value.selectedCapsuleID }?.id ?? CapsuleProfile.batteryID
        onCapsulePreview?(id)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if configurationPending { closeAfterConfiguration = true; return false }
        return true
    }

    func setConfigurationPending(_ pending: Bool) {
        guard configurationPending != pending else { return }
        configurationPending = pending
        tabs.isEnabled = !pending
        if pending {
            window?.makeFirstResponder(nil)
            disableEditing()
        } else {
            draftText.removeAll()
            buildPage()
        }
        sharingController?.setPending(pending)
        if !pending && closeAfterConfiguration {
            closeAfterConfiguration = false
            window?.performClose(nil)
        }
    }

    private func disableEditing() {
        func disable(_ view: NSView) {
            (view as? NSControl)?.isEnabled = false
            view.subviews.forEach(disable)
        }
        if let content = window?.contentView { disable(content) }
    }

    func configurationCompleted(_ result: ConfigurationTransactionResult) {
        sharingController?.completed(result)
    }

    func windowWillClose(_ notification: Notification) {
        commitEditing()
        sharingController?.close(); sharingController = nil
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
        if keyboardMenuInstalled { installKeyboardMenu() }
        let names = sectionTitles
        tabs.segmentCount = names.count
        for (index, name) in names.enumerated() { tabs.setLabel(name, forSegment: index); tabs.setWidth(0, forSegment: index) }
        tabs.selectedSegment = selectedTab
        tabs.setAccessibilityLabel(t("设置分类", "Settings sections"))
        tabs.font = .systemFont(ofSize: 11)
        tabs.frame.size = NSSize(width: 550, height: 28)
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
        // Terminal-style index of the open section (01 / GENERAL … 07 / ABOUT), updated with each page.
        let section = label("", size: 10, mono: true)
        section.textColor = accent
        section.alignment = .right
        section.identifier = NSUserInterfaceItemIdentifier("settings.section")
        place(section, in: content, x: 396, y: 40, width: 200, height: 18)
        sectionLabel = section
        separator(in: content, y: 84)
        buildPage()
    }

    func buildPage() {
        let enteringSection = renderedTab != selectedTab
        let scrollOffset = enteringSection ? nil : (page?.subviews.first { $0 is NSScrollView } as? NSScrollView)?.contentView.bounds.origin
        commitEditing()
        textEdits.removeAll()
        validationMessage = nil
        scrollAnchors.removeAll()
        page?.removeFromSuperview()
        // Bindings own only controls on the currently selected page, never a hidden page tree.
        actions.removeAll(keepingCapacity: true)
        bindings.removeAll(keepingCapacity: true)
        let page = SettingsBackground(frame: NSRect(x: 24, y: 104, width: 572, height: 310))
        self.page = page
        renderedTab = selectedTab
        content.addSubview(page)
        switch selectedTab {
        case 1: animationPage(page)
        case 2: alertsPage(page)
        case 3: telemetryPage(page)
        case 4: capsulesPage(page)
        case 5: rulesPage(page)
        case 6: aboutPage(page)
        default: generalPage(page)
        }
        let anchorOffset = pendingAnchor.flatMap { scrollAnchors[$0] }.map { NSPoint(x: 0, y: max(0, $0 - 12)) }
        pendingAnchor = nil
        if let target = scrollOffset ?? anchorOffset, let scroll = page.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView {
            let maximumY = max(0, (scroll.documentView?.bounds.height ?? 0) - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: target.x, y: min(maximumY, target.y)))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        sectionLabel?.stringValue = String(format: "%02d / %@", selectedTab + 1, Self.sectionCodes[selectedTab])
        // Footer controls are recreated with the page, so their action entries stay valid.
        content.subviews.filter { $0.identifier?.rawValue == "footer" }.forEach { $0.removeFromSuperview() }
        let footer = SettingsBackground(frame: NSRect(x: 0, y: 434, width: 620, height: 46))
        footer.identifier = NSUserInterfaceItemIdentifier("footer")
        content.addSubview(footer)
        separator(in: footer, y: 0)
        // The always-visible action follows the page: Capsules previews the capsule being edited, from any scroll position.
        let previewsCapsule = selectedTab == 4
        let preview = button(previewsCapsule ? t("预览当前胶囊", "Preview Active Capsule") : t("预览本机电量", "Preview Battery"),
                             in: footer, y: 10) { c, _ in
            c.commitEditing()
            if c.selectedTab == 4 { c.previewActiveCapsule() } else { c.onPreview(nil) }
        }
        preview.identifier = NSUserInterfaceItemIdentifier("footer.preview")
        let previewWidth = max(135, ceil(preview.fittingSize.width) + 12)
        preview.frame = NSRect(x: 596 - previewWidth, y: 10, width: previewWidth, height: 28)
        let status = label("", size: 10)
        status.identifier = NSUserInterfaceItemIdentifier("footer.status")
        status.lineBreakMode = .byTruncatingTail
        place(status, in: footer, x: 24, y: 17, width: preview.frame.minX - 36, height: 18)
        validationMessage = status
        updateStatusLine()
        refresh()
        if configurationPending { disableEditing() }
        if enteringSection { flashScrollableContent() }
    }

    private func refresh() {
        if let sharingController { self.sharingController = sharingController.refreshed() }
        if renderedChinese != settings.chinese { rebuild(); return }
        for update in bindings { update(self) }
    }

    @objc private func selectTab(_ sender: NSSegmentedControl) { showSection(sender.selectedSegment) }

    @objc func controlChanged(_ sender: NSControl) { guard !configurationPending else { return }; actions[ObjectIdentifier(sender)]?(self, sender) }

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
