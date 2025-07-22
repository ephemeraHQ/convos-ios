import Foundation
import GRDB

protocol InviteWriterProtocol {
    @discardableResult
    func store(invite: ConvosAPI.InviteDetailsResponse) async throws -> Invite
}

class InviteWriter: InviteWriterProtocol {
    private let databaseWriter: any DatabaseWriter

    init(databaseWriter: any DatabaseWriter) {
        self.databaseWriter = databaseWriter
    }

    func store(invite: ConvosAPI.InviteDetailsResponse) async throws -> Invite {
        let dbInvite = DBInvite(
            id: invite.id,
            conversationId: invite.groupId,
            inviteUrlString: invite.inviteLinkURL,
            maxUses: invite.maxUses,
            usesCount: invite.usesCount,
            status: invite.status.inviteStatus,
            createdAt: invite.createdAt
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
