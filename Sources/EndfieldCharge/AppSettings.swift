import AppKit
import ServiceManagement
import ChargeCore

final class AppSettings {
    var value: Preferences {
        didSet {
            guard value != oldValue else { return }
            if !readingPeer { save() }; onChange?(); onUIChange?()
        }
    }
    private(set) var loginEnabled = false
    private(set) var loginMessage = ""
    var shortcutMessage = "" { didSet { if shortcutMessage != oldValue { onUIChange?() } } }
    var onChange: (() -> Void)?
    // A visible settings window observes independently of the resident application's callback.
    var onUIChange: (() -> Void)?
    private var readingPeer = false
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "preferences"),
           let decoded = try? JSONDecoder().decode(Preferences.self, from: data) {
            value = decoded
        } else { value = Preferences() }
        value.scale = min(1.2, max(0.4, value.scale))
        value.duration = min(10, max(3, value.duration))
        value.lowThreshold = min(40, max(5, value.lowThreshold))
    }

    var chinese: Bool {
        value.language == "zh" || (value.language == "system" &&
            Locale.preferredLanguages.first?.hasPrefix("zh") == true)
    }
    func text(_ zh: String, _ en: String) -> String { chinese ? zh : en }

    func applyFromPeer(_ preferences: Preferences) {
        readingPeer = true
        defer { readingPeer = false }
        value = preferences
    }

    func save() {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: "preferences") }
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refreshLogin()
        } catch {
            refreshLogin()
            loginMessage = error.localizedDescription
        }
        onUIChange?()
    }

    func refreshLogin() {
        let status = SMAppService.mainApp.status
        loginEnabled = status == .enabled
        loginMessage = status == .requiresApproval
            ? text("请在系统设置 → 通用 → 登录项中允许。", "Allow this app in System Settings → General → Login Items.") : ""
        onUIChange?()
    }
}

extension NSColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                  green: CGFloat((rgb >> 8) & 255) / 255,
                  blue: CGFloat(rgb & 255) / 255, alpha: alpha)
    }
}
