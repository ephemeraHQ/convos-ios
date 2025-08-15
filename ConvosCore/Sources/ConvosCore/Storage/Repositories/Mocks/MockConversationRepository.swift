import Combine
import Foundation

public class MockConversationRepository: ConversationRepositoryProtocol {
    public init() {}

    public var conversationPublisher: AnyPublisher<Conversation?, Never> {
        Just(conversation).eraseToAnyPublisher()
    }

    public var conversationId: String {
        conversation.id
    }

    private let conversation: Conversation = .mock()

    public func fetchConversation() throws -> Conversation? {
        conversation
    }
}

class MockDraftConversationRepository: DraftConversationRepositoryProtocol {
    public var inviteRepository: any InviteRepositoryProtocol {
        MockInviteRepository()
    }

    public var conversationId: String {
        conversation.id
    }

    public var messagesRepository: any MessagesRepositoryProtocol {
        MockMessagesRepository(conversation: conversation)
    }

    public var conversationPublisher: AnyPublisher<Conversation?, Never> {
        Just(conversation).eraseToAnyPublisher()
    }

    private let conversation: Conversation = .mock(id: "draft-123")

    public func fetchConversation() throws -> Conversation? {
        conversation
    }
}
