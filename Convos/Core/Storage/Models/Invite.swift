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
        "\(inboxId)-\(code)"
    }

    static func parse(temporaryInviteString: String) -> (inboxId: String, code: String)? {
        Logger.info("Invite.parse: Attempting to parse: '\(temporaryInviteString)'")

        let result = temporaryInviteString.split(separator: "-")
        Logger.info("Invite.parse: Split result count: \(result.count), parts: \(result)")

        guard result.count == 2 else {
            Logger.error("Invite.parse: Expected 2 parts separated by '-', got \(result.count)")
            return nil
        }

        guard let inboxId = result.first, let code = result.last else {
            Logger.error("Invite.parse: Failed to extract inboxId or code from parts")
            return nil
        }

        let parsedResult = (String(inboxId), String(code))
        Logger.info("Invite.parse: Successfully parsed - inboxId: '\(parsedResult.0)', code: '\(parsedResult.1)'")
        return parsedResult
    }
}
