import Combine
import Foundation

extension Conversation {
    public static func mock(
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
            isDraft: false,
            invite: .mock()
        )
    }

    public static func empty(id: String = "") -> Self {
        .init(
            id: id,
            inboxId: "",
            creator: .empty(isCurrentUser: true),
            createdAt: .distantFuture,
            consent: .allowed,
            kind: .group,
            name: "",
            description: "",
            members: [],
            otherMember: nil,
            messages: [],
            isPinned: false,
            isUnread: false,
            isMuted: false,
            lastMessage: nil,
            imageURL: nil,
            isDraft: true,
            invite: nil
        )
    }
}

extension Invite {
    public static func mock() -> Self {
        .init(
            code: "invite_code_123",
            conversationId: "conversation_123",
            inviteSlug: "invite_code_123",
            createdAt: Date(),
            expiresAt: nil,
            maxUses: nil,
            usesCount: 0,
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
