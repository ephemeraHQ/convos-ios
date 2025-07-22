import Foundation
import GRDB

struct Identity: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    let id: String
    let inboxId: String
    let walletAddress: String?

    static let inboxForeignKey: ForeignKey = ForeignKey(["inboxId"])

    static let inbox: BelongsToAssociation<Identity, DBInbox> = belongsTo(
        DBInbox.self,
        key: "identityInbox",
        using: inboxForeignKey
    )
}
