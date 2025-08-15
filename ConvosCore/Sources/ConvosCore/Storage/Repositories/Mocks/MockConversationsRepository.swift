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
            invite: nil
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
            isDraft: false,
            invite: nil
        )
    }
}

extension Invite {
    public static func mock() -> Self {
        .init(
            code: "invite_code_123",
            conversationId: "conversation_123",
            inviteUrlString: "http://convos.org/join/invite_code_123",
            status: .active,
            createdAt: Date(),
            maxUses: 0,
            usesCount: 0,
            autoApprove: false
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

    public func fetchAll() throws -> [Conversation] {
        conversations
    }
}
