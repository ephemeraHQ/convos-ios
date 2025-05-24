import Combine
import Foundation

class MockMessageSender: MessageSender {
    func prepare(text: String) async throws -> String {
        return ""
    }

    func publish() async throws {
    }
}

class MockClientProvder: XMTPClientProvider {
    let mockConversation: Conversation = .mock()

    func messageSender(for conversationId: String) async throws -> (any MessageSender)? {
        return nil
    }
}

class MockMessagingService: ConvosSDK.MessagingServiceProtocol {
    enum MockMessagingServiceError: Error {
        case unauthorized
    }

    private let currentUser: MockUser? = nil

    private let mockClient = MockClientProvder()

    private var messagingStateSubject: CurrentValueSubject<ConvosSDK.MessagingServiceState, Never> =
        .init(.uninitialized)

    var clientPublisher: AnyPublisher<(any XMTPClientProvider)?, Never> {
        Just(mockClient).eraseToAnyPublisher()
    }

    var state: ConvosSDK.MessagingServiceState {
        messagingStateSubject.value
    }

    func start() async throws {
        messagingStateSubject.send(.initializing)
        messagingStateSubject.send(.authorizing)
        messagingStateSubject.send(.ready)
    }

    func stop() {
        messagingStateSubject.send(.stopping)
        messagingStateSubject.send(.uninitialized)
    }

    func userRepository() -> any UserRepositoryProtocol {
        MockUserRepository()
    }

    func profileSearchRepository() -> any ProfileSearchRepositoryProtocol {
        MockProfileSearchRepository()
    }

    func conversationsRepository() -> any ConversationsRepositoryProtocol {
        MockConversationsRepository()
    }

    func conversationRepository(for conversationId: String) -> any ConversationRepositoryProtocol {
        MockConversationRepository()
    }

    func messagesRepository(for conversationId: String) -> any MessagesRepositoryProtocol {
        MockMessagesRepository(conversation: .mock())
    }

    func messageWriter(for conversationId: String) -> any OutgoingMessageWriterProtocol {
        MockOutgoingMessageWriter()
    }

    func messagingStatePublisher() -> AnyPublisher<ConvosSDK.MessagingServiceState, Never> {
        messagingStateSubject.eraseToAnyPublisher()
    }
}
