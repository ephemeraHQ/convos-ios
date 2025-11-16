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

// MARK: - Mock Data
extension MessagesGroup {
    static var mockIncoming: MessagesGroup {
        let sender = ConversationMember.mock(isCurrentUser: false)
        let messages: [AnyMessage] = [
            .message(Message.mock(text: "Hey there!", sender: sender, status: .published)),
            .message(Message.mock(text: "How are you doing today?", sender: sender, status: .published)),
            .message(Message.mock(text: "Let me know when you're free", sender: sender, status: .published))
        ]
        return MessagesGroup(
            id: "mock-incoming-group",
            sender: sender,
            messages: messages,
            unpublished: []
        )
    }

    static var mockOutgoing: MessagesGroup {
        let sender = ConversationMember.mock(isCurrentUser: true)
        let messages: [AnyMessage] = [
            .message(Message.mock(text: "I'm doing great!", sender: sender, status: .published)),
            .message(Message.mock(text: "Thanks for asking 😊", sender: sender, status: .published))
        ]
        return MessagesGroup(
            id: "mock-outgoing-group",
            sender: sender,
            messages: messages,
            unpublished: []
        )
    }

    static var mockMixed: MessagesGroup {
        let sender = ConversationMember.mock(isCurrentUser: true)
        let published: [AnyMessage] = [
            .message(Message.mock(text: "Here's my first message", sender: sender, status: .published)),
            .message(Message.mock(text: "And another one", sender: sender, status: .published))
        ]
        let unpublished: [AnyMessage] = [
            .message(Message.mock(text: "This one is still sending...", sender: sender, status: .unpublished))
        ]
        return MessagesGroup(
            id: "mock-mixed-group",
            sender: sender,
            messages: published,
            unpublished: unpublished
        )
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

// MARK: - Mock Data for MessagesListItemType
extension MessagesListItemType {
    static var mockDate: MessagesListItemType {
        .date(DateGroup(date: Date()))
    }

    static var mockUpdate: MessagesListItemType {
        .update(id: "mock-update", update: ConversationUpdate.mock())
    }

    static var mockIncomingMessages: MessagesListItemType {
        .messages(.mockIncoming)
    }

    static var mockOutgoingMessages: MessagesListItemType {
        .messages(.mockOutgoing)
    }

    static var mockMixedMessages: MessagesListItemType {
        .messages(.mockMixed)
    }

    static var mockConversation: [MessagesListItemType] {
        [
            .mockDate,
            .mockIncomingMessages,
            .mockOutgoingMessages,
            .mockUpdate,
            .mockMixedMessages
        ]
    }
}
