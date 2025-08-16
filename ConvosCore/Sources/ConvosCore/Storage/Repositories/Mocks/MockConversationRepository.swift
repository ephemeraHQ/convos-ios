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
    var inviteRepository: any InviteRepositoryProtocol {
        MockInviteRepository()
    }

    var conversationId: String {
        conversation.id
    }

    var messagesRepository: any MessagesRepositoryProtocol {
        MockMessagesRepository(conversation: conversation)
    }

    var conversationPublisher: AnyPublisher<Conversation?, Never> {
        Just(conversation).eraseToAnyPublisher()
    }

    private let conversation: Conversation = .mock(id: "draft-123")

    func fetchConversation() throws -> Conversation? {
        conversation
    }
}
