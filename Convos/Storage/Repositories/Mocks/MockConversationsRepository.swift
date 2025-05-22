import Combine
import Foundation

extension Conversation {
    static func mock() -> Self {
        .init(
            id: UUID().uuidString,
            creator: .mock(),
            createdAt: Date(),
            kind: .group,
            name: "My Conversation \(Int.random(in: 1..<11))",
            members: [.mock(), .mock()],
            otherMember: .mock(),
            messages: [],
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
