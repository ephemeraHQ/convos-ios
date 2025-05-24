import Combine
import Foundation

class MockMessagingService: ConvosSDK.MessagingServiceProtocol {
    // MARK: - State

    let authService = MockAuthService()

    init() {

    }

    // MARK: - Protocol Conformance

    private var messagingStateSubject: CurrentValueSubject<ConvosSDK.MessagingServiceState, Never> =
        .init(.uninitialized)

    var clientPublisher: AnyPublisher<(any XMTPClientProvider)?, Never> {
        Just(self).eraseToAnyPublisher()
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
        self
    }

    func profileSearchRepository() -> any ProfileSearchRepositoryProtocol {
        self
    }

    func conversationsRepository() -> any ConversationsRepositoryProtocol {
        self
    }

    func conversationRepository(for conversationId: String) -> any ConversationRepositoryProtocol {
        self
    }

    func messagesRepository(for conversationId: String) -> any MessagesRepositoryProtocol {
        self
    }

    func messageWriter(for conversationId: String) -> any OutgoingMessageWriterProtocol {
        self
    }

    func messagingStatePublisher() -> AnyPublisher<ConvosSDK.MessagingServiceState, Never> {
        messagingStateSubject.eraseToAnyPublisher()
    }
}

extension MockMessagingService: UserRepositoryProtocol {
    func getCurrentUser() async throws -> User? {
        return .mock()
    }

    func userPublisher() -> AnyPublisher<User?, Never> {
        Just(nil).eraseToAnyPublisher()
    }
}

extension MockMessagingService: ProfileSearchRepositoryProtocol {
    func search(using query: String) async throws -> [Profile] {
        []
    }
}

extension MockMessagingService: ConversationsRepositoryProtocol {
    func fetchAll() throws -> [Conversation] {
        []
    }

    func conversationsPublisher() -> AnyPublisher<[Conversation], Never> {
        Just([]).eraseToAnyPublisher()
    }
}

extension MockMessagingService: ConversationRepositoryProtocol {
    func conversationPublisher() -> AnyPublisher<Conversation?, Never> {
        Just(nil).eraseToAnyPublisher()
    }
}

extension MockMessagingService: MessagesRepositoryProtocol {
    func fetchAll() throws -> [AnyMessage] {
        []
    }

    func messagesPublisher() -> AnyPublisher<[AnyMessage], Never> {
        Just([]).eraseToAnyPublisher()
    }
}

extension MockMessagingService: OutgoingMessageWriterProtocol {
    func send(text: String) async throws {
    }
}

extension MockMessagingService: XMTPClientProvider {
    func messageSender(for conversationId: String) async throws -> (any MessageSender)? {
        self
    }
}

extension MockMessagingService: MessageSender {
    func prepare(text: String) async throws -> String {
        // return id
        ""
    }
    func publish() async throws {
    }
}
