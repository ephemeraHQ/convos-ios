import Foundation

struct ParsedInvite {
    let inviteId: String
    let inboxId: String
    let code: String
}

struct Invite: Codable, Hashable, Identifiable, Equatable {
    var id: String {
        code
    }
    let code: String
    let conversationId: String
    let inviteUrlString: String
    let status: InviteStatus
    let createdAt: Date
    let maxUses: Int?
    let usesCount: Int
    let inboxId: String // @jarodl temporary workaround

    var temporaryInviteString: String {
        guard !inboxId.isEmpty && !code.isEmpty else { return "" }
        return "\(id)-\(inboxId)-\(code)"
    }

    static func parse(temporaryInviteString: String) -> ParsedInvite? {
        let result = temporaryInviteString.split(separator: "-")
        guard result.count == 3 else {
            return nil
        }
        let id = result[0]
        let inboxId = result[1]
        let code = result[2]
        return .init(inviteId: String(id), inboxId: String(inboxId), code: String(code))
    }
}
