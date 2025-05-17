import Foundation
import GRDB

protocol UserWriterProtocol {
    func storeUser(_ user: ConvosAPIClient.UserResponse) async throws
    func storeUser(_ user: ConvosAPIClient.CreatedUserResponse) async throws
}

class UserWriter: UserWriterProtocol {
    private let databaseWriter: any DatabaseWriter

    init(databaseWriter: any DatabaseWriter) {
        self.databaseWriter = databaseWriter
    }

    func storeUser(_ user: ConvosAPIClient.UserResponse) async throws {
        let identities: [Identity] = user.identities.map {
            Identity(id: $0.id,
                     userId: user.id,
                     walletAddress: $0.turnkeyAddress,
                     xmtpId: $0.xmtpId)
        }
        try await databaseWriter.write { db in
            let existingProfile = try UserProfile
                .filter(Column("userId") == user.id)
                .fetchOne(db)

            let profile = existingProfile ?? UserProfile(
                userId: user.id,
                name: "",
                username: "",
                avatar: nil
            )

            let dbUser = DBUser(id: user.id)
            try dbUser.save(db)

            try profile.save(db)

            let session = Session(currentUserId: user.id)
            try Session.deleteAll(db) // ensure only one row
            try session.save(db)

            try Identity
                .filter(Column("userId") == user.id)
                .deleteAll(db)

            for identity in identities {
                try identity.save(db)
            }
        }
    }

    func storeUser(_ user: ConvosAPIClient.CreatedUserResponse) async throws {
        let identities: [Identity] = [
            Identity(id: user.identity.id,
                     userId: user.id,
                     walletAddress: user.identity.turnkeyAddress,
                     xmtpId: user.identity.xmtpId)
        ]
        let profile: UserProfile = .init(userId: user.id,
                                         name: user.profile.name,
                                         username: user.profile.username,
                                         avatar: user.profile.avatar)
        let dbUser = DBUser(id: user.id)
        try await databaseWriter.write { db in
            try dbUser.save(db)

            let session = Session(currentUserId: user.id)
            try Session.deleteAll(db) // ensure only one row
            try session.save(db)

            for identity in identities {
                try identity.save(db)
            }

            try profile.save(db)
        }
    }
}
