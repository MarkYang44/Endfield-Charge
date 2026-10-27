import AppKit
import UniformTypeIdentifiers
import ChargeCore

/// Native panels and preview data exist only while the user opens Sharing.
final class SettingsSharingController: NSWindowController, NSWindowDelegate {
    private let settings: AppSettings
    private let renderedChinese: Bool
    private let submit: (ConfigurationTransactionAction) throws -> Void
    private var prepared: ConfigurationShare?
    private var previewFailed = false
    private let mode = NSPopUpButton(frame: .zero, pullsDown: false)
    private let summary = NSTextField(wrappingLabelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let applyButton = NSButton()
    private var controls: [NSControl] = []
    private(set) var pending = false
    var onClose: (() -> Void)?

    init(settings: AppSettings, submit: @escaping (ConfigurationTransactionAction) throws -> Void) {
        self.settings = settings; self.submit = submit; renderedChinese = settings.chinese
        let view = SharingBackground(frame: NSRect(x: 0, y: 0, width: 600, height: 476))
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.contentView = view; window.delegate = self; window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.title = t("分享与导入", "Sharing & Import")
        window.center()
        addLabel(t("/// 配置传输", "/// CONFIGURATION TRANSFER"), at: 22, size: 11, color: NSColor(rgb: 0xC6CA4C))
        addLabel(t("分享胶囊与规则", "Share Capsules & Rules"), at: 48, size: 21, weight: .bold)
        addLabel(t("仅分享胶囊、规则、配色与轮播设置。快捷键、语言、显示器及登录启动保留本机设置。",
                   "Shares capsules, rules, colors and rotation settings. Shortcuts, language, display and login settings stay local."), at: 88, height: 48, size: 12, color: .secondaryLabelColor)
        addButton(t("导出…", "Export…"), x: 24, y: 146, width: 148, action: #selector(exportFile))
        addButton(t("选择导入文件…", "Choose Import File…"), x: 182, y: 146, width: 193, action: #selector(importFile))
        addButton(t("撤销上次导入…", "Undo Last Import…"), x: 385, y: 146, width: 191, action: #selector(restore))
        mode.addItems(withTitles: [t("合并（保留本机内容）", "Merge (keep local content)"), t("替换分享内容", "Replace shared content")])
        mode.frame = NSRect(x: 24, y: 193, width: 552, height: 28)
        mode.target = self; mode.action = #selector(updatePreview)
        mode.setAccessibilityLabel(t("导入方式", "Import mode"))
        view.addSubview(mode); controls.append(mode)
        summary.frame = NSRect(x: 24, y: 238, width: 552, height: 78)
        summary.font = .systemFont(ofSize: 12); view.addSubview(summary)
        addLabel(t("新导入规则默认停用。替换会关闭常驻与轮播；合并保留本机开关。应用前会备份完整配置。",
                   "New rules start disabled. Replace turns off persistent display and rotation; merge keeps local switches. A full backup is saved before applying."), at: 326, height: 51, size: 11, color: .systemOrange)
        status.frame = NSRect(x: 24, y: 394, width: 352, height: 58)
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor; view.addSubview(status)
        applyButton.title = t("应用导入…", "Apply Import…"); applyButton.bezelStyle = .rounded
        applyButton.target = self; applyButton.action = #selector(confirmImport)
        applyButton.frame = NSRect(x: 392, y: 410, width: 184, height: 30)
        view.addSubview(applyButton); controls.append(applyButton)
        updatePreview()
    }
    required init?(coder: NSCoder) { fatalError("Programmatic sharing window") }
    private func t(_ zh: String, _ en: String) -> String { settings.text(zh, en) }
    var importMode: ConfigurationImportMode { mode.indexOfSelectedItem == 1 ? .replace : .merge }

    private func addLabel(_ text: String, at y: CGFloat, height: CGFloat = 28, size: CGFloat,
                          weight: NSFont.Weight = .regular, color: NSColor = .labelColor) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight); label.textColor = color
        label.frame = NSRect(x: 24, y: y, width: 552, height: height)
        window?.contentView?.addSubview(label)
    }
    private func addButton(_ title: String, x: CGFloat, y: CGFloat, width: CGFloat, action: Selector) {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded; button.frame = NSRect(x: x, y: y, width: width, height: 30)
        window?.contentView?.addSubview(button); controls.append(button)
    }
    func prepareImport(_ data: Data) throws {
        let share = try ConfigurationShare.decode(data)
        prepared = share; status.stringValue = ""; updatePreview()
    }
    /// Keep a visible preview current when another settings control changes its baseline or language.
    func refreshed() -> SettingsSharingController {
        guard renderedChinese != settings.chinese else { updatePreview(); return self }
        let replacement = SettingsSharingController(settings: settings, submit: submit)
        replacement.onClose = onClose
        replacement.prepared = prepared
        replacement.mode.selectItem(at: mode.indexOfSelectedItem)
        replacement.setPending(pending)
        if let frame = window?.frame { replacement.window?.setFrame(frame, display: false) }
        let visible = window?.isVisible == true
        close()
        if visible { replacement.showWindow(nil) }
        return replacement
    }

    @objc private func updatePreview() {
        if previewFailed { status.stringValue = ""; previewFailed = false }
        applyButton.isEnabled = false
        guard let prepared else {
            summary.stringValue = t("选择 .endfield.json 文件，确认预览后再应用。取消或关闭窗口不会修改配置。",
                                    "Choose an .endfield.json file to review before applying. Canceling or closing leaves your configuration unchanged.")
            return
        }
        do {
            let s = try prepared.preview(mode: importMode, local: settings.value).summary
            summary.stringValue = settings.chinese
                ? "胶囊：新增 \(s.addedProfiles) · 复用 \(s.reusedProfiles) · 替换 \(s.replacedProfiles)\n规则：新增 \(s.addedRules) · 复用 \(s.reusedRules) · 替换 \(s.replacedRules)\n默认停用 \(s.disabledRules) 条新规则 · 丢弃 \(s.discardedReferences.count) 个无效引用"
                : "Capsules: \(s.addedProfiles) added · \(s.reusedProfiles) reused · \(s.replacedProfiles) replaced\nRules: \(s.addedRules) added · \(s.reusedRules) reused · \(s.replacedRules) replaced\nNew rules disabled: \(s.disabledRules) · \(s.discardedReferences.count) invalid references discarded"
            applyButton.isEnabled = !pending
        } catch { previewFailed = true; showError(error) }
    }
    func setPending(_ pending: Bool) {
        self.pending = pending
        controls.forEach { $0.isEnabled = !pending }
        updatePreview()
        if pending { status.stringValue = t("正在等待主进程确认…", "Waiting for the resident app…") }
    }
    func completed(_ result: ConfigurationTransactionResult) {
        previewFailed = false
        if result.status == .applied {
            prepared = nil
            status.stringValue = t("配置已应用。", "Configuration applied.")
        } else if result.status == .stale {
            status.stringValue = t("本机配置已更改。请重新检查预览后重试。", "Local settings changed. Review the preview and try again.")
        } else {
            switch result.failure {
            case .backupUnavailable:
                status.stringValue = t("无法读取上次导入前的备份，当前配置未更改。", "Could not read the previous import backup. Your configuration is unchanged.")
            case .storageFailure:
                status.stringValue = t("无法保存导入前备份，当前配置未更改。请检查磁盘与目录权限。", "Could not save the backup. Your configuration is unchanged. Check disk space and folder access.")
            case .cancelled:
                status.stringValue = t("操作已取消。", "Operation canceled.")
            default:
                status.stringValue = t("导入配置无效，当前配置未更改。", "The imported configuration is invalid. Your configuration is unchanged.")
            }
        }
        updatePreview()
    }
    func showError(_ error: Error) {
        status.stringValue = Self.errorText(error, chinese: settings.chinese)
    }
    static func errorText(_ error: Error, chinese: Bool) -> String {
        let pair: (String, String)
        switch error {
        case ConfigurationShareError.fileTooLarge: pair = ("配置文件超过 128 KiB 上限。", "The configuration exceeds the 128 KiB limit.")
        case ConfigurationShareError.unsupportedFormat: pair = ("无法识别此配置格式，请选择 Endfield 分享文件。", "Unrecognized format. Choose an Endfield share file.")
        case ConfigurationShareError.unsupportedVersion: pair = ("此配置版本不受支持。", "This configuration version is unsupported.")
        case ConfigurationShareError.profileLimit: pair = ("合并后超过 \(ConfigurationLimits.maximumProfiles) 个胶囊。请减少本机内容或使用替换。", "This would exceed \(ConfigurationLimits.maximumProfiles) capsules. Remove local items or use Replace.")
        case ConfigurationShareError.ruleLimit: pair = ("合并后超过 \(ConfigurationLimits.maximumRules) 条规则。请减少本机内容或使用替换。", "This would exceed \(ConfigurationLimits.maximumRules) rules. Remove local items or use Replace.")
        case ConfigurationShareError.invalidField: pair = ("配置包含无效、重复或越界字段。请检查来源文件。", "The configuration contains invalid, duplicate or out-of-range fields. Check the source file.")
        case is DecodingError: pair = ("配置文件损坏，或包含不支持的字段值。", "The configuration is malformed or contains unsupported values.")
        case is SettingsConfigurationSession.SessionError: pair = ("主进程尚未就绪，或仍有操作未完成。", "The resident app is not ready or another operation is pending.")
        default: pair = ("无法读写配置文件。请检查文件与目录权限后重试。", "Could not read or write the configuration file. Check file and folder access and try again.")
        }
        return chinese ? pair.0 : pair.1
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !pending }
    func windowWillClose(_ notification: Notification) { onClose?() }
    @objc private func exportFile() {
        guard !pending, let window else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Endfield.endfield.json"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            do {
                try ConfigurationShare(preferences: self.settings.value).encoded().write(to: url, options: .atomic)
                self.status.stringValue = self.t("分享文件已导出。", "Share file exported.")
            } catch { self.showError(error) }
        }
    }
    @objc private func importFile() {
        guard !pending, let window else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            do { try self.prepareImport(ConfigurationFileIO.readBounded(url)) }
            catch { self.prepared = nil; self.updatePreview(); self.showError(error) }
        }
    }
    @objc private func confirmImport() {
        guard !pending, let prepared else { return }
        do { _ = try prepared.preview(mode: importMode, local: settings.value) }
        catch { showError(error); return }
        confirm(title: t("应用此导入？", "Apply this import?"),
                detail: importMode == .replace
                    ? t("这会替换本机所有分享范围内的内容。导入前将保存完整备份。", "This replaces all local content in the shared scope. A full backup will be saved first.")
                    : t("这会将预览内容合并到本机。导入前将保存完整备份。", "This merges the previewed content into your configuration. A full backup will be saved first.")) { [weak self] in
            guard let self else { return }
            self.dispatch(.importShare(prepared, mode: self.importMode))
        }
    }
    @objc private func restore() {
        guard !pending else { return }
        confirm(title: t("撤销上次导入？", "Undo the last import?"),
                detail: t("将恢复上次导入前的完整配置，包括此后修改的本机偏好。登录启动注册不变。", "Restores the full configuration from before the last import, including local settings changed since then. Login registration stays as it is.")) { [weak self] in
            self?.dispatch(.restoreBackup)
        }
    }
    private func confirm(title: String, detail: String, action: @escaping () -> Void) {
        guard let window else { return }
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail; alert.alertStyle = .warning
        alert.addButton(withTitle: t("确认", "Confirm")); alert.addButton(withTitle: t("取消", "Cancel"))
        alert.beginSheetModal(for: window) { response in if response == .alertFirstButtonReturn { action() } }
    }
    private func dispatch(_ action: ConfigurationTransactionAction) {
        do { try submit(action) } catch { showError(error) }
    }
}

private final class SharingBackground: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) { NSColor(rgb: 0x262425).setFill(); dirtyRect.intersection(bounds).fill() }
}

extension SettingsWindowController {
    func showSharing() {
        guard !configurationPending else { return }
        commitEditing()
        if sharingController == nil {
            sharingController = SettingsSharingController(settings: settings) { [weak self] action in
                guard let self, let onConfigurationRequest = self.onConfigurationRequest else {
                    throw SettingsConfigurationSession.SessionError.unavailable
                }
                self.commitEditing()
                try onConfigurationRequest(action)
            }
            sharingController?.onClose = { [weak self] in self?.sharingController = nil }
        }
        sharingController?.showWindow(nil)
        sharingController?.window?.makeKeyAndOrderFront(nil)
    }
}
