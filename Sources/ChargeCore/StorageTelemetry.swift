import Foundation

public struct StorageTelemetry: Codable, Equatable {
    public let totalBytes: UInt64
    public let freeBytes: UInt64
    public let availableBytes: UInt64
    public let path: String
    public let fileSystem: String
    public var usedBytes: UInt64 { totalBytes - freeBytes }
    /// APFS volumes share container space. This is filesystem accounting, not physical drive capacity.
    public var usedFraction: Double { Double(usedBytes) / Double(totalBytes) }

    public init?(totalBytes: UInt64, freeBytes: UInt64, availableBytes: UInt64, path: String, fileSystem: String) {
        guard totalBytes > 0, freeBytes <= totalBytes, availableBytes <= freeBytes else { return nil }
        self.totalBytes = totalBytes; self.freeBytes = freeBytes; self.availableBytes = availableBytes
        self.path = path; self.fileSystem = fileSystem
    }
    private enum CodingKeys: String, CodingKey { case totalBytes, freeBytes, availableBytes, path, fileSystem }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let total = try values.decode(UInt64.self, forKey: .totalBytes)
        let free = try values.decode(UInt64.self, forKey: .freeBytes)
        let available = try values.decode(UInt64.self, forKey: .availableBytes)
        guard let value = Self(totalBytes: total, freeBytes: free, availableBytes: available,
            path: try values.decode(String.self, forKey: .path), fileSystem: try values.decode(String.self, forKey: .fileSystem)) else {
            throw DecodingError.dataCorruptedError(forKey: .totalBytes, in: values, debugDescription: "Invalid filesystem capacities")
        }
        self = value
    }
}
