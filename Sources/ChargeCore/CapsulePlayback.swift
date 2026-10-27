import Foundation

public struct CapsulePlayback: Codable, Equatable {
    public var persistent: Bool
    public var rotationEnabled: Bool
    public var profileIDs: [String]
    public var intervalSeconds: Double

    public init(persistent: Bool = false, rotationEnabled: Bool = false,
                profileIDs: [String] = [], intervalSeconds: Double = 15) {
        self.persistent = persistent; self.rotationEnabled = rotationEnabled
        self.profileIDs = profileIDs; self.intervalSeconds = intervalSeconds
    }

    public mutating func normalize(profiles: [CapsuleProfile]) {
        let valid = Set(profiles.map(\.id))
        var seen = Set<String>()
        var normalized: [String] = []
        for id in profileIDs where valid.contains(id) && seen.insert(id).inserted {
            normalized.append(id)
            if normalized.count == ConfigurationLimits.maximumProfiles { break }
        }
        profileIDs = normalized
        if profileIDs.isEmpty { rotationEnabled = false }
        intervalSeconds = intervalSeconds.isFinite ? min(600, max(10, intervalSeconds)) : 15
    }

    /// A single result needs no rotation timer. An empty normalized queue uses the selection.
    public func effectiveProfileIDs(selectedID: String, profiles: [CapsuleProfile]) -> [String] {
        var value = self; value.normalize(profiles: profiles)
        if value.rotationEnabled && !value.profileIDs.isEmpty { return value.profileIDs }
        if profiles.contains(where: { $0.id == selectedID }) { return [selectedID] }
        if profiles.contains(where: { $0.id == CapsuleProfile.batteryID }) { return [CapsuleProfile.batteryID] }
        return profiles.first.map { [$0.id] } ?? []
    }

    private enum CodingKeys: String, CodingKey { case persistent, rotationEnabled, profileIDs, intervalSeconds }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(persistent: try values.decodeIfPresent(Bool.self, forKey: .persistent) ?? false,
            rotationEnabled: try values.decodeIfPresent(Bool.self, forKey: .rotationEnabled) ?? false,
            intervalSeconds: try values.decodeIfPresent(Double.self, forKey: .intervalSeconds) ?? 15)
        if values.contains(.profileIDs) {
            var ids = try values.nestedUnkeyedContainer(forKey: .profileIDs)
            for _ in 0..<ConfigurationLimits.maximumProfiles where !ids.isAtEnd {
                let entry = try ids.superDecoder()
                if let id = try? String(from: entry) { profileIDs.append(id) }
            }
        }
    }
}
