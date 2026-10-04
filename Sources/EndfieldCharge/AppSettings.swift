import AppKit
import SwiftUI
import ServiceManagement
import ChargeCore

final class AppSettings: ObservableObject {
    @Published var value: Preferences { didSet { save(); onChange?() } }
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var loginMessage = ""
    @Published var shortcutMessage = ""
    var onChange: (() -> Void)?
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

    func save() {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: "preferences") }
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refreshLogin()
            if SMAppService.mainApp.status == .requiresApproval {
                loginMessage = text("请在系统设置 → 通用 → 登录项中允许。", "Allow this app in System Settings → General → Login Items.")
            } else { loginMessage = "" }
        } catch {
            refreshLogin()
            loginMessage = error.localizedDescription
        }
    }

    func refreshLogin() {
        loginEnabled = SMAppService.mainApp.status == .enabled
    }
}

extension NSColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                  green: CGFloat((rgb >> 8) & 255) / 255,
                  blue: CGFloat(rgb & 255) / 255, alpha: alpha)
    }
}
