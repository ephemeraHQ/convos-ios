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
        return "\(inboxId)-\(code)"
    }

    static func parse(temporaryInviteString: String) -> (inboxId: String, code: String)? {
        let result = temporaryInviteString.split(separator: "-")
        guard result.count == 2 else {
            return nil
        }
        guard let inboxId = result.first, let code = result.last else {
            return nil
        }
        return (String(inboxId), String(code))
    }
}
