import Combine
import Foundation
import XMTPiOS

// swiftlint: disable force_unwrapping

class MockMessagingService: MessagingServiceProtocol {
    // MARK: - State

    let currentUser: User = .mock()
    let allUsers: [Profile]
    let conversations: [Conversation]
    private var unpublishedMessages: [AnyMessage] = []

    private var currentConversation: Conversation?
    private var messages: [AnyMessage]
    private var messagesSubject: CurrentValueSubject<[AnyMessage], Never>
    private var messageTimer: Timer?
    private var messagingStateSubject: CurrentValueSubject<MessagingServiceState, Never> =
        .init(.uninitialized)

    init() {
        let users = Self.randomUsers()
        allUsers = users
        conversations = Self.randomConversations(with: users)
        currentConversation = conversations.randomElement()
        let initialMessages = Self.generateRandomMessages(
            count: Int.random(in: 5...50),
            conversation: currentConversation ?? conversations[0],
            users: allUsers
        )
        self.messages = initialMessages
        self.messagesSubject = CurrentValueSubject(initialMessages)

        Task {
            try await start()
        }
    }

    // MARK: - Protocol Conformance

    var clientPublisher: AnyPublisher<(any XMTPClientProvider)?, Never> {
        Just(self).eraseToAnyPublisher()
    }

    var state: MessagingServiceState {
        messagingStateSubject.value
    }

    func start() async throws {
        messagingStateSubject.send(.initializing)
        messagingStateSubject.send(.authorizing)
        messagingStateSubject.send(.ready)
        startMessageTimer()
    }

    func stop() {
        messageTimer?.invalidate()
        messageTimer = nil
        messagingStateSubject.send(.stopping)
        messagingStateSubject.send(.uninitialized)
    }

    func userRepository() -> any UserRepositoryProtocol {
        self
    }

    func profileSearchRepository() -> any ProfileSearchRepositoryProtocol {
        self
    }

    func draftConversationComposer() -> any DraftConversationComposerProtocol {
        MockDraftConversationComposer()
    }

    func conversationsRepository() -> any ConversationsRepositoryProtocol {
        self
    }

    func conversationRepository(for conversationId: String) -> any ConversationRepositoryProtocol {
        if let found = conversations.first(where: { $0.id == conversationId }) {
            currentConversation = found
        }
        return self
    }

    func messagesRepository(for conversationId: String) -> any MessagesRepositoryProtocol {
        if let found = conversations.first(where: { $0.id == conversationId }) {
            currentConversation = found
        }
        return self
    }

    func messageWriter(for conversationId: String) -> any OutgoingMessageWriterProtocol {
        self
    }

    var messagingStatePublisher: AnyPublisher<MessagingServiceState, Never> {
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
    func search(using query: String) async throws -> [ProfileSearchResult] {
        allUsers.filter { $0.name.contains(query) }.map { profile in
                .init(profile: profile, inboxId: profile.id)
        }
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
    var conversation: Conversation? {
        conversations.randomElement()
    }

    var conversationPublisher: AnyPublisher<Conversation?, Never> {
        Just(conversation).eraseToAnyPublisher()
    }

    func fetchConversation() throws -> Conversation? {
        conversation
    }
}

extension MockMessagingService: MessagesRepositoryProtocol {
    func fetchAll() throws -> [AnyMessage] {
        messages
    }

    var conversationMessagesPublisher: AnyPublisher<ConversationMessages, Never> {
        let conversationId = currentConversation?.id ?? ""
        return messagesSubject
            .map { (conversationId, $0) }
            .eraseToAnyPublisher()
    }
}

extension MockMessagingService: OutgoingMessageWriterProtocol {
    func send(text: String) async throws {
        _ = try await prepare(text: text)
        try await publish()
    }
}

extension MockMessagingService: ConversationSender {
    func add(members inboxIds: [String]) async throws {
    }

    func remove(members inboxIds: [String]) async throws {
    }
}

extension MockMessagingService: XMTPClientProvider {
    func canMessage(identity: String) async throws -> Bool {
        true
    }

    func canMessage(identities: [String]) async throws -> [String: Bool] {
        return Dictionary(uniqueKeysWithValues: identities.map { ($0, true) })
    }

    func prepareConversation() async throws -> ConversationSender {
        self
    }

    func newConversation(with memberInboxIds: [String],
                         name: String,
                         description: String,
                         imageUrl: String) async throws -> String {
        return UUID().uuidString
    }

    func newConversation(with memberInboxId: String) async throws -> String {
        return UUID().uuidString
    }

    func conversation(with id: String) async throws -> XMTPiOS.Conversation? {
        nil
    }

    func messageSender(for conversationId: String) async throws -> (any MessageSender)? {
        self
    }
}

extension MockMessagingService: MessageSender {
    func prepare(text: String) async throws -> String {
        guard let conversation = currentConversation else { return "" }
        let message: AnyMessage = .message(
            .init(id: UUID().uuidString,
                  conversation: conversation,
                  sender: currentUser.profile,
                  source: .outgoing,
                  status: .published,
                  content: .text(text),
                  reactions: []
                 )
        )
        unpublishedMessages.append(message)
        return message.base.id
    }

    func publish() async throws {
        messages.append(contentsOf: unpublishedMessages)
        unpublishedMessages.removeAll()
        messagesSubject.send(messages)
    }
}

// MARK: - Mock Data Generation

extension MockMessagingService {
    static func randomConversations(with users: [Profile]) -> [Conversation] {
        (0..<Int.random(in: 4...10)).map { index in
            Self.generateRandomConversation(id: "\(index)", from: users)
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

    static func generateRandomConversation(id: String, from users: [Profile]) -> Conversation {
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
            id: id,
            creator: randomCreator,
            date: Date(),
            kind: kind,
            name: randomName,
            members: randomMembers,
            otherMember: otherMember,
            messages: [],
            lastMessage: .init(
                text: TextGenerator.getString(
                    of: Int.random(in: 1...10)),
                createdAt: Date().addingTimeInterval(-TimeInterval.random(in: 0...86400))
            )
        )
    }

    private func startMessageTimer() {
        messageTimer?.invalidate()
        scheduleNextMessage()
    }

    private func scheduleNextMessage() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let interval = TimeInterval.random(in: 0.0...2.0)
            messageTimer = Timer.scheduledTimer(
                timeInterval: interval,
                target: self,
                selector: #selector(handleTimer),
                userInfo: nil,
                repeats: false
            )
        }
    }

    @objc
    private func handleTimer() {
        generateRandomMessageAndAppend()
        scheduleNextMessage()
    }

    private func generateRandomMessageAndAppend() {
        guard let conversation = currentConversation ?? conversations.first else { return }
        let sender = conversation.members.randomElement() ?? allUsers.randomElement() ?? currentUser.profile
        let message = Message(
            id: UUID().uuidString,
            conversation: conversation,
            sender: sender,
            source: .incoming,
            status: .published,
            content: .text(TextGenerator.getString(of: Int.random(in: 1...20))),
            reactions: []
        )
        let anyMessage = AnyMessage.message(message)
        messages.append(anyMessage)
        messagesSubject.send(messages)
    }

    static func generateRandomMessages(count: Int, conversation: Conversation, users: [Profile]) -> [AnyMessage] {
        (0..<count).map { _ in
            let sender = conversation.members.randomElement() ?? users.randomElement() ?? users[0]
            let message = Message(
                id: UUID().uuidString,
                conversation: conversation,
                sender: sender,
                source: .incoming,
                status: .published,
                content: .text(TextGenerator.getString(of: Int.random(in: 1...20))),
                reactions: []
            )
            return AnyMessage.message(message)
        }
    }
}

// swiftlint: enable force_unwrapping
