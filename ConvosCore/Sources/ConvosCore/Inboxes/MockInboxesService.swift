import Combine
import Foundation

public class MockInboxesService: SessionManagerProtocol {
    public var messagingService: AnyMessagingService {
        MockMessagingService()
    }

    public func shouldDisplayNotification(for conversationId: String) async -> Bool {
        true
    }

    public init() {
    }

    public var authState: AnyPublisher<AuthServiceState, Never> {
        Just(AuthServiceState.unknown).eraseToAnyPublisher()
    }

    public func deleteAllData() async throws {
    }

    public func deleteConversation(conversationId: String) async throws {
    }

    public func conversationsRepository(for consent: [Consent]) -> any ConversationsRepositoryProtocol {
        MockConversationsRepository()
    }

    public func conversationsCountRepo(for consent: [Consent], kinds: [ConversationKind]) -> any ConversationsCountRepositoryProtocol {
        self
    }

    public func inviteRepository(for conversationId: String) -> any InviteRepositoryProtocol {
        MockInviteRepository()
    }

    public func conversationRepository(for conversationId: String) -> any ConversationRepositoryProtocol {
        MockConversationRepository()
    }

    public func messagesRepository(for conversationId: String) -> any MessagesRepositoryProtocol {
        MockMessagesRepository(conversation: .mock(id: conversationId))
    }
}

extension MockInboxesService: ConversationsCountRepositoryProtocol {
    public var conversationsCount: AnyPublisher<Int, Never> {
        Just(1).eraseToAnyPublisher()
    }

    public func fetchCount() throws -> Int {
        1
    }
}
