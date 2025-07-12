import Combine
import Foundation

extension Conversation {
    static func mock(
        id: String = UUID().uuidString,
        creator: ConversationMember = .mock(),
        date: Date = Date(),
        consent: Consent = .allowed,
        kind: ConversationKind = .dm,
        name: String = "The Convo",
        description: String = "Where we talk about all things Convos.",
        members: [ConversationMember] = [],
        otherMember: ConversationMember? = .mock(),
        messages: [Message] = [],
        lastMessage: MessagePreview? = nil
    ) -> Self {
        .init(
            id: id,
            inboxId: UUID().uuidString,
            creator: creator,
            createdAt: Date(),
            consent: consent,
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

    lazy var conversationsPublisher: AnyPublisher<[Conversation], Never> = {
        Just(conversations).eraseToAnyPublisher()
    }()

    func fetchAll() throws -> [Conversation] {
        conversations
    }
}
