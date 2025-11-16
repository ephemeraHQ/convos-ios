import ConvosCore
import Foundation

/// Transforms an array of `AnyMessage` into an array of `MessagesListItemType` for display in SwiftUI
@MainActor
final class MessagesListProcessor {
    // MARK: - Constants
    private static let hourInSeconds: TimeInterval = 3600

    // MARK: - Public Methods

    /// Transforms messages into display items for the messages list
    /// - Parameter messages: Array of messages from the repository
    /// - Returns: Array of items ready for display in the messages list
    static func process(_ messages: [AnyMessage]) -> [MessagesListItemType] {
        // 1. Filter out messages that shouldn't be shown
        let visibleMessages = messages.filter { $0.base.content.showsInMessagesList }

        // 2. Sort messages by date (they should already be sorted, but ensure it)
        let sortedMessages = visibleMessages.sorted { $0.base.date < $1.base.date }

        // 3. Process all messages together, keeping unpublished messages in their groups
        return processMessages(sortedMessages)
    }

    // MARK: - Private Methods

    private static func processMessages(_ messages: [AnyMessage]) -> [MessagesListItemType] {
        guard !messages.isEmpty else { return [] }

        var items: [MessagesListItemType] = []
        var currentGroup: [AnyMessage] = []
        var currentSenderId: String?
        var lastMessageDate: Date?

        for (index, message) in messages.enumerated() {
            // Check if this is an update message
            if case .update(let update) = message.base.content {
                // Flush current group if exists
                if !currentGroup.isEmpty, let senderId = currentSenderId {
                    items.append(createMessageGroup(
                        messages: currentGroup,
                        senderId: senderId
                    ))
                    currentGroup = []
                    currentSenderId = nil
                }

                // Add the update item
                items.append(.update(id: message.base.id, update: update))
                lastMessageDate = message.base.date
                continue
            }

            // Check if we need a date separator
            var addedDateSeparator = false
            if let lastDate = lastMessageDate {
                let timeDifference = message.base.date.timeIntervalSince(lastDate)
                if timeDifference > hourInSeconds {
                    // Flush current group before adding date separator
                    if !currentGroup.isEmpty, let senderId = currentSenderId {
                        items.append(createMessageGroup(
                            messages: currentGroup,
                            senderId: senderId
                        ))
                        currentGroup = []
                        currentSenderId = nil
                    }

                    items.append(.date(DateGroup(date: message.base.date)))
                    addedDateSeparator = true
                }
            } else if index == 0 {
                // Add date for the first message
                items.append(.date(DateGroup(date: message.base.date)))
                addedDateSeparator = true
            }

            // Group messages by sender
            // If we added a date separator, always start a new group
            // Otherwise, only start a new group if the sender changed
            if addedDateSeparator {
                // Always start a new group after a date separator
                currentGroup = [message]
                currentSenderId = message.base.sender.id
            } else if let currentId = currentSenderId, currentId != message.base.sender.id {
                // Sender changed, flush the current group
                items.append(createMessageGroup(
                    messages: currentGroup,
                    senderId: currentId
                ))
                currentGroup = [message]
                currentSenderId = message.base.sender.id
            } else {
                // Same sender and no date separator, continue the group
                currentGroup.append(message)
                currentSenderId = message.base.sender.id
            }

            lastMessageDate = message.base.date
        }

        // Flush the last group
        if !currentGroup.isEmpty, let senderId = currentSenderId {
            items.append(createMessageGroup(
                messages: currentGroup,
                senderId: senderId
            ))
        }

        return items
    }

    private static func createMessageGroup(
        messages: [AnyMessage],
        senderId: String
    ) -> MessagesListItemType {
        guard let firstMessage = messages.first else {
            fatalError("Cannot create message group with empty messages array")
        }

        // Separate published and unpublished messages
        let published = messages.filter { $0.base.status == .published }
        let unpublished = messages.filter { $0.base.status != .published }

        let group = MessagesGroup(
            id: "group-\(senderId)-\(firstMessage.base.date.timeIntervalSince1970)",
            sender: firstMessage.base.sender,
            messages: published,
            unpublished: unpublished
        )

        return .messages(group)
    }
}
