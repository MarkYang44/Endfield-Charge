import Foundation

/// The private pipe protocol carries bounded configuration and snapshots, without runtime history or image data.
public struct SettingsMessage: Codable {
    /// Maximum encoded payload per frame, excluding its newline. Shared by both pipe endpoints.
    public static let maximumPayloadBytes = 131_072
    public enum Command: String, Codable {
        case ready, changed, state, show, preview, demoCharge, demoBattery, screen, closed, closeAck, reopen, telemetry, visibility, previewCapsule
    }
    public var command: Command
    public var preferences: Preferences?
    public var revision: Int?
    public var shortcutMessage: String?
    public var tab: Int?
    public var frame: String?
    public var displayID: UInt32?
    public var telemetry: TelemetrySnapshot?
    public var profileID: String?
    public var visible: Bool?
    public init(_ command: Command, preferences: Preferences? = nil, revision: Int? = nil,
                shortcutMessage: String? = nil, tab: Int? = nil, frame: String? = nil, displayID: UInt32? = nil,
                telemetry: TelemetrySnapshot? = nil, visible: Bool? = nil, profileID: String? = nil) {
        self.command = command; self.preferences = preferences; self.revision = revision
        self.shortcutMessage = shortcutMessage; self.tab = tab; self.frame = frame; self.displayID = displayID
        self.telemetry = telemetry
        self.visible = visible; self.profileID = profileID
    }
}
