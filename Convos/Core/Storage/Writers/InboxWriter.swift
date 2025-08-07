import Foundation
import GRDB

protocol InboxWriterProtocol {
    func storeInbox(inboxId: String,
                    type: InboxType,
                    provider: InboxProvider,
                    providerId: String,
                    user: ConvosAPI.UserResponse,
                    profile: ConvosAPI.ProfileResponse) async throws
    func storeInbox(inboxId: String,
                    user: ConvosAPI.CreatedUserResponse,
                    type: InboxType,
                    provider: InboxProvider,
                    providerId: String) async throws
    func deleteInbox(inboxId: String) async throws
}

final class InboxWriter: InboxWriterProtocol {
    private let databaseWriter: any DatabaseWriter

    init(databaseWriter: any DatabaseWriter) {
        self.databaseWriter = databaseWriter
    }

    func storeInbox(inboxId: String,
                    type: InboxType,
                    provider: InboxProvider,
                    providerId: String,
                    user: ConvosAPI.UserResponse,
                    profile: ConvosAPI.ProfileResponse) async throws {
        let identities: [Identity] = user.identities.map {
            .init(
                id: $0.id,
                inboxId: inboxId,
                walletAddress: $0.identityAddress
            )
        }
        try await databaseWriter.write { db in
            let session = Session()
            try? session.save(db)

            let dbInbox = DBInbox(
                inboxId: inboxId,
                type: type,
                provider: provider,
                providerId: providerId
            )
            try dbInbox.save(db)

            let memberProfile: MemberProfile = .init(inboxId: inboxId,
                                                     name: profile.name,
                                                     avatar: profile.avatar)
            let member: Member = .init(inboxId: inboxId)
            try member.save(db)
            try memberProfile.save(db)

            for identity in identities {
                try identity.save(db)
            }
        }
    }

    func storeInbox(inboxId: String,
                    user: ConvosAPI.CreatedUserResponse,
                    type: InboxType,
                    provider: InboxProvider,
                    providerId: String) async throws {
        let identities: [Identity] = [
            .init(
                id: user.identity.id,
                inboxId: inboxId,
                walletAddress: user.identity.identityAddress
            )
        ]
        let member: Member = .init(inboxId: inboxId)
        let memberProfile: MemberProfile = .init(inboxId: inboxId,
                                                 name: user.profile.name,
                                                 avatar: user.profile.avatar)
        let dbInbox = DBInbox(
            inboxId: inboxId,
            type: type,
            provider: provider,
            providerId: providerId
        )
        try await databaseWriter.write { db in
            let session = Session()
            try? session.save(db)

            try dbInbox.save(db)
            try member.save(db)
            try memberProfile.save(db)

            for identity in identities {
                try identity.save(db)
            }
        }
    }

    func deleteInbox(inboxId: String) async throws {
        try await databaseWriter.write { db in
            guard let inbox = try DBInbox.fetchOne(db, id: inboxId) else {
                Logger.error("Inbox not found, skipping delete")
                return
            }
            let conversations = DBConversation.filter(DBConversation.Columns.inboxId == inboxId)
            try inbox.delete(db)
            try conversations.deleteAll(db)
            Logger.info("Successfully deleted inbox \(inbox.inboxId)")
        }
    }
}
