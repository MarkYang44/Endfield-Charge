import Foundation

/// The private pipe protocol is small and contains no runtime history or image data.
public struct SettingsMessage: Codable {
    public enum Command: String, Codable {
        case ready, changed, state, show, preview, demoCharge, demoBattery, screen, closed, closeAck, reopen, telemetry, visibility
    }
    public var command: Command
    public var preferences: Preferences?
    public var revision: Int?
    public var shortcutMessage: String?
    public var tab: Int?
    public var frame: String?
    public var displayID: UInt32?
    public var telemetry: TelemetrySnapshot?
    public var visible: Bool?
    public init(_ command: Command, preferences: Preferences? = nil, revision: Int? = nil,
                shortcutMessage: String? = nil, tab: Int? = nil, frame: String? = nil, displayID: UInt32? = nil,
                telemetry: TelemetrySnapshot? = nil, visible: Bool? = nil) {
        self.command = command; self.preferences = preferences; self.revision = revision
        self.shortcutMessage = shortcutMessage; self.tab = tab; self.frame = frame; self.displayID = displayID
        self.telemetry = telemetry
        self.visible = visible
    }
}
