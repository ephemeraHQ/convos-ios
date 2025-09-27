import Foundation
import GRDB

public protocol InviteWriterProtocol {
    func generate(for conversation: DBConversation,
                  maxUses: Int?,
                  expiresAt: Date?) async throws -> Invite
}

enum InviteWriterError: Error {
    case failedEncodingInvitePayload
}

class InviteWriter: InviteWriterProtocol {
    private let identityStore: any KeychainIdentityStoreProtocol
    private let databaseWriter: any DatabaseWriter

    init(identityStore: any KeychainIdentityStoreProtocol,
         databaseWriter: any DatabaseWriter) {
        self.identityStore = identityStore
        self.databaseWriter = databaseWriter
    }

    func generate(for conversation: DBConversation, maxUses: Int? = nil, expiresAt: Date? = nil) async throws -> Invite {
        let existingInvite = try? await self.databaseWriter.read { db in
            try? DBInvite
                .filter(DBInvite.Columns.conversationId == conversation.id)
                .filter(DBInvite.Columns.creatorInboxId == conversation.inboxId)
                .fetchOne(db)
        }
        if let existingInvite {
            Logger.info("Existing invite found for conversation: \(conversation.id), \(existingInvite)")
            return existingInvite.hydrateInvite()
        }

        let identity = try await identityStore.identity()
        let privateKey: Data = identity.keys.privateKey.secp256K1.bytes
        let urlSlug = try SignedInvite.slug(for: conversation, privateKey: privateKey)
        Logger.info("Generated URL slug: \(urlSlug)")

        let dbInvite = DBInvite(
            creatorInboxId: conversation.inboxId,
            conversationId: conversation.id,
            urlSlug: urlSlug
        )
        try await databaseWriter.write { db in
            try Member(inboxId: conversation.inboxId).save(db, onConflict: .ignore)
            try DBConversationMember(
                conversationId: conversation.id,
                inboxId: conversation.inboxId,
                role: .member,
                consent: .allowed,
                createdAt: Date()
            )
            .save(db, onConflict: .ignore)
            let memberProfile = MemberProfile(
                conversationId: conversation.id,
                inboxId: conversation.inboxId,
                name: nil,
                avatar: nil
            )
            try? memberProfile.insert(db, onConflict: .ignore)
            try dbInvite.save(db)
        }
        return dbInvite.hydrateInvite()
    }
}
