import Foundation
import GRDB

protocol UserWriterProtocol {
    func storeUser(_ user: ConvosAPI.UserResponse,
                   profile: ConvosAPI.ProfileResponse,
                   inboxId: String) async throws
    func storeUser(_ user: ConvosAPI.CreatedUserResponse,
                   inboxId: String) async throws
}

class UserWriter: UserWriterProtocol {
    private let databaseWriter: any DatabaseWriter

    init(databaseWriter: any DatabaseWriter) {
        self.databaseWriter = databaseWriter
    }

    func storeUser(_ user: ConvosAPI.UserResponse,
                   profile: ConvosAPI.ProfileResponse,
                   inboxId: String) async throws {
        let identities: [Identity] = user.identities.map {
            Identity(id: $0.id,
                     userId: user.id,
                     walletAddress: $0.turnkeyAddress,
                     xmtpId: $0.xmtpId)
        }
        let member: Member = .init(inboxId: inboxId)
        try await databaseWriter.write { db in
            let profile = UserProfile(
                userId: user.id,
                name: profile.name,
                username: profile.username,
                avatar: profile.avatar
            )
            let memberProfile: MemberProfile = .init(inboxId: inboxId,
                                                     name: profile.name,
                                                     username: profile.username,
                                                     avatar: profile.avatar)

            try member.save(db)
            try memberProfile.save(db)
            let dbUser = DBUser(id: user.id, inboxId: inboxId)
            try dbUser.save(db)

            try profile.save(db)

            let session = Session(userId: user.id)
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

    func storeUser(_ user: ConvosAPI.CreatedUserResponse,
                   inboxId: String) async throws {
        let identities: [Identity] = [
            Identity(id: user.identity.id,
                     userId: user.id,
                     walletAddress: user.identity.turnkeyAddress,
                     xmtpId: user.identity.xmtpId)
        ]
        let member: Member = .init(inboxId: inboxId)
        let memberProfile: MemberProfile = .init(inboxId: inboxId,
                                                 name: user.profile.name,
                                                 username: user.profile.username,
                                                 avatar: user.profile.avatar)
        let profile: UserProfile = .init(userId: user.id,
                                         name: user.profile.name,
                                         username: user.profile.username,
                                         avatar: user.profile.avatar)
        let dbUser = DBUser(id: user.id, inboxId: inboxId)
        try await databaseWriter.write { db in
            try member.save(db)
            try memberProfile.save(db)
            try dbUser.save(db)

            let session = Session(userId: user.id)
            try Session.deleteAll(db) // ensure only one row
            try session.save(db)

            for identity in identities {
                try identity.save(db)
            }

            try profile.save(db)
        }
    }
}
