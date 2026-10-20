import Foundation
import CryptoKit

/// The private pipe protocol carries bounded configuration and snapshots, without runtime history or image data.
public struct SettingsMessage: Codable {
    /// Maximum encoded payload per frame, excluding its newline. Shared by both pipe endpoints.
    public static let maximumPayloadBytes = 131_072
    public enum Command: String, Codable {
        case ready, changed, state, show, preview, demoCharge, demoBattery, screen, closed, closeAck, reopen, telemetry, visibility, previewCapsule
        case configurationRequest, configurationResult
    }
    public var command: Command
    public var preferences: Preferences?
    public var revision: Int?
    public var baselineDigest: String?
    public var shortcutMessage: String?
    public var tab: Int?
    public var frame: String?
    public var displayID: UInt32?
    public var telemetry: TelemetrySnapshot?
    public var profileID: String?
    public var visible: Bool?
    public var transactionRequest: ConfigurationTransactionRequest?
    public var transactionResult: ConfigurationTransactionResult?
    public init(_ command: Command, preferences: Preferences? = nil, revision: Int? = nil,
                shortcutMessage: String? = nil, tab: Int? = nil, frame: String? = nil, displayID: UInt32? = nil,
                telemetry: TelemetrySnapshot? = nil, visible: Bool? = nil, profileID: String? = nil,
                transactionRequest: ConfigurationTransactionRequest? = nil, transactionResult: ConfigurationTransactionResult? = nil, baselineDigest: String? = nil) {
        self.baselineDigest = baselineDigest
        self.command = command; self.preferences = preferences; self.revision = revision
        self.shortcutMessage = shortcutMessage; self.tab = tab; self.frame = frame; self.displayID = displayID
        self.telemetry = telemetry
        self.visible = visible; self.profileID = profileID
        self.transactionRequest = transactionRequest; self.transactionResult = transactionResult
    }

    /// Call before dispatch so oversized transactions surface an error to the caller.
    public func encodedBounded() throws -> Data {
        let bytes = try JSONEncoder().encode(self)
        guard bytes.count <= Self.maximumPayloadBytes else { throw ConfigurationShareError.fileTooLarge }
        return bytes
    }
}


public enum ConfigurationTransactionAction: Codable, Equatable {
    case importShare(ConfigurationShare, mode: ConfigurationImportMode)
    case restoreBackup
}

/// Both tokens are required: status-menu edits may occur without changing the helper UI revision.
public struct ConfigurationTransactionRequest: Codable, Equatable {
    public let requestID: String
    public let expectedRevision: Int
    public let baselineDigest: String
    public let action: ConfigurationTransactionAction

    public init(requestID: String, expectedRevision: Int, baseline: Preferences, action: ConfigurationTransactionAction) throws {
        self.requestID = requestID; self.expectedRevision = expectedRevision
        baselineDigest = try Self.digest(baseline); self.action = action
        try validate()
    }
    public func matches(preferences: Preferences, revision: Int) throws -> Bool {
        try validate()
        guard expectedRevision == revision else { return false }
        return baselineDigest == (try Self.digest(preferences))
    }
    public func validate() throws {
        guard ConfigurationTextLimit.identifier.accepted(requestID) == requestID, expectedRevision >= 0,
              baselineDigest.count == 64, baselineDigest.allSatisfy({ "0123456789abcdef".contains($0) }) else {
            throw ConfigurationShareError.invalidField("transaction")
        }
        if case .importShare(let share, _) = action { try share.validate() }
    }
    public static func digest(_ preferences: Preferences) throws -> String {
        SHA256.hash(data: try canonicalPreferences(preferences)).map { String(format: "%02x", $0) }.joined()
    }

    /// Canonicalizes unordered Set encoding explicitly; sortedKeys alone does not sort arrays.
    public static func canonicalPreferences(_ preferences: Preferences) throws -> Data {
        _ = try ConfigurationShare(preferences: preferences)
        guard preferences.scale.isFinite, preferences.duration.isFinite else { throw ConfigurationShareError.invalidField("preferences") }
        let encoded = try JSONEncoder().encode(preferences)
        var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        object["shortcutModifiers"] = preferences.shortcutModifiers.map(\.rawValue).sorted()
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// Backup files are exact full snapshots, not legacy documents that may silently migrate.
    public static func validatedPreferences(_ data: Data) throws -> Preferences {
        guard data.count <= SettingsMessage.maximumPayloadBytes else { throw ConfigurationShareError.fileTooLarge }
        let preferences = try JSONDecoder().decode(Preferences.self, from: data)
        var original = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let modifiers = original?["shortcutModifiers"] as? [String] else { throw ConfigurationShareError.invalidField("preferences.shortcutModifiers") }
        original?["shortcutModifiers"] = modifiers.sorted()
        let canonical = try JSONSerialization.jsonObject(with: canonicalPreferences(preferences)) as! NSDictionary
        guard let original, NSDictionary(dictionary: original).isEqual(canonical) else { throw ConfigurationShareError.invalidField("preferences") }
        return preferences
    }

    private enum CodingKeys: String, CodingKey { case requestID, expectedRevision, baselineDigest, action }
    public init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try v.decode(String.self, forKey: .requestID)
        expectedRevision = try v.decode(Int.self, forKey: .expectedRevision)
        baselineDigest = try v.decode(String.self, forKey: .baselineDigest)
        action = try v.decode(ConfigurationTransactionAction.self, forKey: .action)
        try validate()
    }
}

public enum ConfigurationTransactionStatus: String, Codable { case applied, stale, rejected }
public enum ConfigurationTransactionFailure: String, Codable {
    case invalidConfiguration, backupUnavailable, storageFailure, cancelled
}
/// Authoritative preferences and revision accompany this in SettingsMessage after a commit.
public struct ConfigurationTransactionResult: Codable, Equatable {
    public let requestID: String
    public let status: ConfigurationTransactionStatus
    public let failure: ConfigurationTransactionFailure?
    public init(requestID: String, status: ConfigurationTransactionStatus, failure: ConfigurationTransactionFailure? = nil) {
        self.requestID = requestID; self.status = status; self.failure = failure
    }
}
