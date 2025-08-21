import CryptoKit
import Foundation
import GRDB

public struct PushNotificationRegistration: Codable, FetchableRecord, PersistableRecord, Hashable {
    public static let databaseTableName: String = "push_notification_registration"

    public enum Columns {
        static let identityId: Column = Column(CodingKeys.identityId)
        static let registrationHash: Column = Column(CodingKeys.registrationHash)
        static let registeredAt: Column = Column(CodingKeys.registeredAt)
    }

    public let identityId: String
    public let registrationHash: String
    public let registeredAt: Date

    public init(identityId: String, deviceId: String, pushToken: String, installationId: String) {
        self.identityId = identityId
        self.registrationHash = Self.computeHash(
            deviceId: deviceId,
            pushToken: pushToken,
            identityId: identityId,
            installationId: installationId
        )
        self.registeredAt = Date()
    }

    /// Compute SHA256 hash of registration parameters
    public static func computeHash(deviceId: String, pushToken: String, identityId: String, installationId: String) -> String {
        let combined = "\(deviceId)|\(pushToken)|\(identityId)|\(installationId)"
        let data = Data(combined.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

extension PushNotificationRegistration {
    /// Check if this registration matches the given parameters
    public func matches(deviceId: String, pushToken: String, identityId: String, installationId: String) -> Bool {
        let currentHash = Self.computeHash(
            deviceId: deviceId,
            pushToken: pushToken,
            identityId: identityId,
            installationId: installationId
        )
        return self.registrationHash == currentHash
    }
}
