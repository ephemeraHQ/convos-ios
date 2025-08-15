import Foundation
import GRDB

public protocol InviteWriterProtocol {
    @discardableResult
    func store(invite: ConvosAPI.PublicInviteDetailsResponse, conversationId: String, inboxId: String) async throws -> Invite
    @discardableResult
    func store(invite: ConvosAPI.InviteDetailsResponse, inboxId: String) async throws -> Invite
}

class InviteWriter: InviteWriterProtocol {
    private let databaseWriter: any DatabaseWriter

    init(databaseWriter: any DatabaseWriter) {
        self.databaseWriter = databaseWriter
    }

    func store(invite: ConvosAPI.PublicInviteDetailsResponse, conversationId: String, inboxId: String) async throws -> Invite {
        let dbInvite = DBInvite(
            id: invite.id,
            conversationId: conversationId,
            inviteUrlString: invite.inviteLinkURL,
            maxUses: nil,
            usesCount: 0,
            status: .active, // @jarodl do we want this to come back from the public API endpoint?
            createdAt: Date(),
            autoApprove: true
        )
        try await databaseWriter.write { db in
            try dbInvite.save(db)
        }
        return dbInvite.hydrateInvite()
    }

    func store(invite: ConvosAPI.InviteDetailsResponse, inboxId: String) async throws -> Invite {
        let dbInvite = DBInvite(
            id: invite.id,
            conversationId: invite.groupId,
            inviteUrlString: invite.inviteLinkURL,
            maxUses: invite.maxUses,
            usesCount: invite.usesCount,
            status: invite.status.inviteStatus,
            createdAt: invite.createdAt,
            autoApprove: invite.autoApprove
        )
        try await databaseWriter.write { db in
            try dbInvite.save(db)
        }
        return dbInvite.hydrateInvite()
    }
}

extension ConvosAPI.InviteCodeStatus {
    var inviteStatus: InviteStatus {
        switch self {
        case .active:
            return .active
        case .expired:
            return .expired
        case .disabled:
            return .disabled
        }
    }
}
