import ConvosCore
import Foundation

struct MessagesGroup: Identifiable, Equatable {
    let id: String
    let sender: ConversationMember // The sender of all messages in this group
    let messages: [AnyMessage] // Contains only published messages
    let unpublished: [AnyMessage] // Contains unpublished messages (failed, unpublished, etc.)

    /// All messages in this group (published + unpublished)
    var allMessages: [AnyMessage] {
        messages + unpublished
    }

    static func == (lhs: MessagesGroup, rhs: MessagesGroup) -> Bool {
        lhs.id == rhs.id &&
        lhs.sender == rhs.sender &&
        lhs.messages == rhs.messages &&
        lhs.unpublished == rhs.unpublished
    }
}

enum MessagesListItemType: Identifiable, Equatable {
    /// Shows metadata changes, new members being added, etc
    /// Ex: "Louis joined by invitation"
    case update(id: String, update: ConversationUpdate)

    /// Shows a timestamp for when the next message in the list was sent
    /// Shown only if the time between messages was greater than an hour
    case date(DateGroup)

    /// Messages sent by the same sender
    case messages(MessagesGroup)

    var id: String {
        switch self {
        case .update(let id, _):
            return "update-\(id)"
        case .date(let dateGroup):
            return "date-\(dateGroup.date.timeIntervalSince1970)"
        case .messages(let group):
            return group.id
        }
    }

    var isMessagesGroupSentByCurrentUser: Bool {
        switch self {
        case .messages(let group):
            return group.sender.isCurrentUser
        default:
            return false
        }
    }
}
