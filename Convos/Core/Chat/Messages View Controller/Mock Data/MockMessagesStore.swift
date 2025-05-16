import Combine
import Foundation

/// Takes messages coming from a MessageService and delivers them in display
/// types.
final class MockMessagesStore: MessagesStoreProtocol {
    var updates: AnyPublisher<MessagingServiceUpdate, Never> {
        messagingService.messages(for: "")
            .map { messages in
                let sections = self.mapMessagesToSections(messages: messages)
                return .init(sections: sections, requiresIsolatedProcess: false)
            }
            .eraseToAnyPublisher()
    }

    private let currentUser: MockUser

    let messagingService: MockMessagesService

    init() {
        self.currentUser = MockUser(name: "You")
        self.messagingService = MockMessagesService(currentUser: currentUser)
    }

    func loadInitialMessages() async -> [MessagesCollectionSection] {
        let messages = await self.messagingService.loadInitialMessages()
        return mapMessagesToSections(messages: messages)
    }

    func loadPreviousMessages() async -> [MessagesCollectionSection] {
        let messages = await self.messagingService.loadPreviousMessages()
        return mapMessagesToSections(messages: messages)
    }

    func sendMessage(_ kind: Message.Kind) async -> [MessagesCollectionSection] {
        switch kind {
        case .text(let string):
            if let messages = try? await self.messagingService.sendMessage(to: "", content: string) {
                return mapMessagesToSections(messages: messages)
            }
        default:
            break
        }
        return []
    }

    func mapMessagesToSections(messages: [any ConvosSDK.RawMessageType]) -> [MessagesCollectionSection] {
        let cells: [MessagesCollectionCell] = messages
            .sorted(by: { lhs, rhs in
                lhs.timestamp < rhs.timestamp
            })
            .map { rawMessage in
                let owner: MockUser = MockUser(name: rawMessage.sender.profile.name)
                let message = Message(
                    id: rawMessage.id,
                    date: rawMessage.timestamp,
                    kind: .text(rawMessage.content),
                    owner: User(
                        id: rawMessage.sender.id,
                        identities: [],
                        profile: .init(
                            id: "",
                            userId: rawMessage.sender.id,
                            name: rawMessage.sender.profile.name,
                            username: rawMessage.sender.profile.username,
                            avatar: nil
                        )
                    ),
                                      type: owner.id == self.currentUser.id ? .outgoing : .incoming,
                                      status: .delivered
)
                return MessagesCollectionCell.message(message, bubbleType: .normal)
            }
        let sections = [MessagesCollectionSection(id: 0, title: "", cells: cells)]
        return sections
    }
}
