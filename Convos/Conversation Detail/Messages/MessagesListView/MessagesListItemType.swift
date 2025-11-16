import ConvosCore
import Foundation

struct MessagesGroup {
    let profile: Profile
    let messages: [AnyMessage]
}

enum MessagesListItemType {
    /// An Invite to this Convo
    /// Shown if the current user is the creator of the group
    case invite(Invite)

    /// Info about the current Convo, shown if the current user is not the group creator
    case info(Conversation)

    /// Shows metadata changes, new members being added, etc
    /// Ex: "Louis joined by invitation"
    case update(ConversationUpdate)

    /// Shows a timestamp for when the next message in the list was sent
    /// Shown only if the time between messages was greater than an hour
    case date(DateGroup)

    /// Messages sent by the same sender
    case messages(MessagesGroup)
}
