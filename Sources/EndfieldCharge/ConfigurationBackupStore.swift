import Foundation
import ChargeCore

/// The resident calls save before its single import commit, and load only for an explicit restore.
/// Login-item registration lives outside Preferences and is never backed up or restored here.
final class ConfigurationBackupStore {
    let fileURL: URL
    private let directory: URL

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.markyang.endfieldcharge", isDirectory: true)) {
        self.directory = directory
        fileURL = directory.appendingPathComponent("previous-import-preferences.json", isDirectory: false)
    }

    func save(_ preferences: Preferences) throws {
        let bytes = try ConfigurationTransactionRequest.canonicalPreferences(preferences)
        // Roundtrip validation prevents a forgiving encoder from silently saving a changed snapshot.
        guard try ConfigurationTransactionRequest.validatedPreferences(bytes) == preferences else {
            throw ConfigurationShareError.invalidField("backup.preferences")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try bytes.write(to: fileURL, options: .atomic)
    }

    func load() throws -> Preferences {
        // Check the on-disk size before reading. The second bound also handles an intervening change.
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let size = attributes[.size] as? NSNumber,
              size.uint64Value <= UInt64(SettingsMessage.maximumPayloadBytes) else { throw ConfigurationShareError.fileTooLarge }
        return try ConfigurationTransactionRequest.validatedPreferences(Data(contentsOf: fileURL))
    }
}
