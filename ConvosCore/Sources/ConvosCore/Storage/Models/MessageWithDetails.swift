import Foundation
import GRDB

struct MessageWithDetails: Codable, FetchableRecord, PersistableRecord, Hashable {
    let message: DBMessage
    let messageSender: ConversationMemberProfileWithRole
    let messageReactions: [DBMessage]
    let sourceMessage: DBMessage?
}

struct MessageWithDetailsAndReplies: Codable, FetchableRecord, PersistableRecord, Hashable {
    let message: DBMessage
    let sender: ConversationMemberProfileWithRole
    let reactions: [DBMessage]
    let replies: [DBMessage]
}
