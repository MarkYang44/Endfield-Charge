import Foundation

/// User-visible character limits also need a byte bound: one grapheme can contain many scalars.
public struct ConfigurationTextLimit {
    public static let name = Self(characters: 32, utf8Bytes: 1024)
    public static let identifier = Self(characters: 64, utf8Bytes: 256)
    public let characters: Int
    public let utf8Bytes: Int

    /// A trimmed prefix of whole graphemes; never splits a composed character to meet the budget.
    public func bounded(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = "", count = 0, bytes = 0
        for character in trimmed {
            let size = character.utf8.count
            guard count < characters, size <= utf8Bytes - bytes else { break }
            result.append(character); count += 1; bytes += size
        }
        return result
    }

    /// Editors reject invalid drafts instead of silently saving a truncated name.
    public func accepted(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= utf8Bytes, trimmed.count <= characters else { return nil }
        return trimmed
    }
}
