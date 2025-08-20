import Foundation
import GRDB

public struct Identity: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    public let id: String
    public let inboxId: String
    public let walletAddress: String?

    static let inboxForeignKey: ForeignKey = ForeignKey(["inboxId"])

    static let inbox: BelongsToAssociation<Identity, DBInbox> = belongsTo(
        DBInbox.self,
        key: "identityInbox",
        using: inboxForeignKey
    )
}
