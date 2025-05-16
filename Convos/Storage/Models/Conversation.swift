import Foundation
import GRDB

struct Conversation: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    let id: String
    let isPinned: Bool
    let isUnread: Bool
    let isMuted: Bool
}
