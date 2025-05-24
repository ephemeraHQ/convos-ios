import Combine
import Foundation

extension Conversation {
    static func mock(
        id: String = UUID().uuidString,
        creator: Profile = .mock(),
        date: Date = Date(),
        kind: ConversationKind = .dm,
        name: String = "The Convo",
        members: [Profile] = [],
        otherMember: Profile? = .mock(),
        messages: [Message] = []
    ) -> Self {
        .init(
            id: id,
            creator: creator,
            createdAt: Date(),
            kind: kind,
            name: name,
            members: members,
            otherMember: otherMember,
            messages: messages,
            isPinned: false,
            isUnread: false,
            isMuted: false,
            lastMessage: nil,
            imageURL: nil
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
