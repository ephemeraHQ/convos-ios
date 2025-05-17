import Foundation
import GRDB

struct Member: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    enum Role: Codable, Hashable {
        case member, admin, superAdmin
    }

    enum Consent: Hashable, Codable {
        case allowed, denied, unknown
    }

    static func primaryKey(inboxId: String,
                           conversationId: String) -> String {
        "\(inboxId)|\(conversationId)"
    }

    var id: String {
        Self.primaryKey(inboxId: inboxId,
                        conversationId: conversationId)
    }
    let inboxId: String
    let conversationId: String
    let role: Role
    let consent: Consent
}
