import Combine
import Foundation

// swiftlint: disable force_unwrapping

class MockMessagingService: ConvosSDK.MessagingServiceProtocol {
    // MARK: - State

    let currentUser: User = .mock()
    let allUsers: [Profile]
    let conversations: [Conversation]

    init() {
        let users = Self.randomUsers()
        allUsers = users
        conversations = Self.randomConversations(with: users)
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
        return currentUser
    }

    func userPublisher() -> AnyPublisher<User?, Never> {
        Just(currentUser).eraseToAnyPublisher()
    }
}

extension MockMessagingService: ProfileSearchRepositoryProtocol {
    func search(using query: String) async throws -> [Profile] {
        allUsers.filter { $0.name.contains(query) }
    }
}

extension MockMessagingService: ConversationsRepositoryProtocol {
    func fetchAll() throws -> [Conversation] {
        conversations
    }

    func conversationsPublisher() -> AnyPublisher<[Conversation], Never> {
        Just(conversations).eraseToAnyPublisher()
    }
}

extension MockMessagingService: ConversationRepositoryProtocol {
    func conversationPublisher() -> AnyPublisher<Conversation?, Never> {
        Just(conversations.randomElement()).eraseToAnyPublisher()
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

// MARK: - Mock Data Generation

extension MockMessagingService {
    static func randomConversations(with users: [Profile]) -> [Conversation] {
        (0..<Int.random(in: 4...10)).map { _ in
            Self.generateRandomConversation(from: users)
        }
    }

    static func randomUsers() -> [Profile] {
        [
            .mock(name: "Alice Johnson"),
            .mock(name: "Bob Smith"),
            .mock(name: "Carol Williams"),
            .mock(name: "David Brown"),
            .mock(name: "Emma Davis"),
            .mock(name: "Frank Miller"),
            .mock(name: "Grace Wilson"),
            .mock(name: "Henry Taylor"),
            .mock(name: "Isabella Martinez"),
            .mock(name: "James Anderson")
        ]
    }

    static func generateRandomConversation(from users: [Profile]) -> Conversation {
        var availableUsers = users
        let randomCreator = availableUsers.randomElement()!
        availableUsers.removeAll { $0 == randomCreator }

        let isDirectMessage = Bool.random()
        let kind: ConversationKind = isDirectMessage ? .dm : .group

        let memberCount = isDirectMessage ? 1 : Int.random(in: 1..<availableUsers.count)
        let otherMember = isDirectMessage ? availableUsers.randomElement()! : nil
        let randomMembers = isDirectMessage ? [otherMember!, randomCreator] : Array(
            availableUsers.shuffled().prefix(memberCount)
        )

        let randomName = isDirectMessage ? otherMember!.name : [
            "Team Discussion",
            "Project Planning",
            "Coffee Chat",
            "Weekend Plans",
            "Book Club",
            "Gaming Group",
            "Study Group"
        ].randomElement()!

        return .mock(
            creator: randomCreator,
            date: Date(),
            kind: kind,
            name: randomName,
            members: randomMembers,
            otherMember: otherMember,
            messages: []
        )
    }
}

// swiftlint: enable force_unwrapping
