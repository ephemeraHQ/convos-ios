import Foundation
import GRDB

public protocol PushNotificationRegistrationWriterProtocol {
    func storeRegistration(deviceId: String,
                           pushToken: String,
                           identityId: String,
                           installationId: String) async throws
    func getLastRegistration(for identityId: String) async throws -> PushNotificationRegistration?
    func hasValidRegistration(deviceId: String,
                              pushToken: String,
                              identityId: String,
                              installationId: String) async throws -> Bool
    func clearRegistrations(for identityId: String) async throws
}

final class PushNotificationRegistrationWriter: PushNotificationRegistrationWriterProtocol {
    private let databaseWriter: any DatabaseWriter

    init(databaseWriter: any DatabaseWriter) {
        self.databaseWriter = databaseWriter
    }

    func storeRegistration(deviceId: String,
                           pushToken: String,
                           identityId: String,
                           installationId: String) async throws {
        try await databaseWriter.write { db in
            let registration = PushNotificationRegistration(
                identityId: identityId,
                deviceId: deviceId,
                pushToken: pushToken,
                installationId: installationId
            )

            // Replace any existing registration for this identity
            try PushNotificationRegistration
                .filter(PushNotificationRegistration.Columns.identityId == identityId)
                .deleteAll(db)

            try registration.save(db)

            Logger.info("Stored push notification registration hash for identity: \(identityId)")
        }
    }

    func getLastRegistration(for identityId: String) async throws -> PushNotificationRegistration? {
        try await databaseWriter.read { db in
            try PushNotificationRegistration
                .filter(PushNotificationRegistration.Columns.identityId == identityId)
                .order(PushNotificationRegistration.Columns.registeredAt.desc)
                .fetchOne(db)
        }
    }

    func hasValidRegistration(deviceId: String,
                              pushToken: String,
                              identityId: String,
                              installationId: String) async throws -> Bool {
        guard let lastRegistration = try await getLastRegistration(for: identityId) else {
            return false
        }

        return lastRegistration.matches(
            deviceId: deviceId,
            pushToken: pushToken,
            identityId: identityId,
            installationId: installationId
        )
    }

    func clearRegistrations(for identityId: String) async throws {
        try await databaseWriter.write { db in
            try PushNotificationRegistration
                .filter(PushNotificationRegistration.Columns.identityId == identityId)
                .deleteAll(db)

            Logger.info("Cleared push notification registrations for identity: \(identityId)")
        }
    }
}
