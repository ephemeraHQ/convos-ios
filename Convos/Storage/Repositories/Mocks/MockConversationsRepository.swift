import Combine
import Foundation

class MockConversationsRepository: ConversationsRepositoryProtocol {
    private let conversations: [Conversation] = [
        .init(
            id: "1",
            creator: .mock(),
            kind: .dm,
            topic: "",
            members: [.mock(), .mock()],
            otherMember: .mock(),
            messages: [],
            isPinned: false,
            isUnread: false,
            isMuted: false,
            lastMessage: nil,
            imageURL: nil
        )
    ]
    func fetchAll() throws -> [Conversation] {
        conversations
    }

    func conversationsPublisher() -> AnyPublisher<[Conversation], Never> {
        Just(conversations).eraseToAnyPublisher()
    }
}
