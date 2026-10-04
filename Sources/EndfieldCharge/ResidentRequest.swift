import Foundation

/// Small local requests keep CLI entry points useful when the menu-bar resident already owns the lock.
enum ResidentRequest: String {
    case preview, settings, telemetry, chargeDemo, batteryDemo
    static let name = Notification.Name("com.markyang.endfieldcharge.request")

    static func action(arguments: [String]) -> ResidentRequest {
        if arguments.contains("--telemetry") { return .telemetry }
        if arguments.contains("--settings") { return .settings }
        if arguments.contains("--demo") { return .chargeDemo }
        if arguments.contains("--preview-unplug") { return .batteryDemo }
        return .preview
    }

    func send(to pid: Int32) {
        DistributedNotificationCenter.default().postNotificationName(Self.name, object: String(pid),
            userInfo: ["action": rawValue], deliverImmediately: true)
    }
}
