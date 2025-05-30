import Combine
import Foundation

extension Conversation {
    static func mock(
        id: String = UUID().uuidString,
        creator: Profile = .mock(),
        date: Date = Date(),
        kind: ConversationKind = .dm,
        name: String = "The Convo",
        description: String = "Where we talk about all things Convos.",
        members: [Profile] = [],
        otherMember: Profile? = .mock(),
        messages: [Message] = [],
        lastMessage: MessagePreview? = nil
    ) -> Self {
        .init(
            id: id,
            creator: creator,
            createdAt: Date(),
            kind: kind,
            name: name,
            description: description,
            members: members,
            otherMember: otherMember,
            messages: messages,
            isPinned: false,
            isUnread: false,
            isMuted: false,
            lastMessage: lastMessage,
            imageURL: nil,
            isDraft: false
        )
    }
}

class MockConversationsRepository: ConversationsRepositoryProtocol {
    private let conversations: [Conversation] = [
        .mock(),
        .mock(),
        .mock(),
        .mock()
    ]

    func fetchAll() throws -> [Conversation] {
        conversations
    }

    func conversationsPublisher() -> AnyPublisher<[Conversation], Never> {
        Just(conversations).eraseToAnyPublisher()
    }
}
