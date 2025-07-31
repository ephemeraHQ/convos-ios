import Foundation

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

    static func parse(temporaryInviteString: String) -> (inviteId: String, inboxId: String, code: String)? {
        let result = temporaryInviteString.split(separator: "-")
        guard result.count == 3 else {
            return nil
        }
        let id = result[0]
        let inboxId = result[1]
        let code = result[2]
        return (String(id), String(inboxId), String(code))
    }
}
