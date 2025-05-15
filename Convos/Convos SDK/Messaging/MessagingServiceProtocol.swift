import Combine
import Foundation

public extension ConvosSDK {
    protocol User {
        var id: String { get }
        var name: String { get }
        var username: String? { get }
        var displayName: String? { get }
        var walletAddress: String? { get }
        var chainId: Int64? { get }
        var avatarURL: URL? { get }
        func sign(message: String) async throws -> Data?
    }

    protocol RawMessageType {
        var id: String { get }
        var content: String { get }
        var sender: any User { get }
        var timestamp: Date { get }
        var replies: [any RawMessageType] { get }
    }

    protocol ConversationType {
        var id: String { get }
//        var participants: [CTUser] { get }
        var otherParticipant: (any User)? { get async throws }
        var lastMessage: (any RawMessageType)? { get async throws }
        var isPinned: Bool { get }
        var isUnread: Bool { get }
        var isRequest: Bool { get }
        var isMuted: Bool { get }
        var timestamp: Date { get }
        var amount: Double? { get }
    }

    protocol MessagingServiceProtocol {
        func start() async throws
        func stop() async

        func conversations() async throws -> [ConversationType]
        func conversationsStream() async -> AsyncThrowingStream<any ConversationType, any Error>

        func sendMessage(to address: String, content: String) async throws -> [any RawMessageType]
        func messages(for address: String) -> AnyPublisher<[any RawMessageType], Never>
        func messagingStatePublisher() -> AnyPublisher<MessagingServiceState, Never>
        func loadInitialMessages() async -> [any RawMessageType]
        func loadPreviousMessages() async -> [any RawMessageType]
        var state: MessagingServiceState { get }
    }

    enum MessagingServiceState {
        case uninitialized
        case initializing
        case authorizing
        case ready
        case stopping
        case error(Error)
    }
}

struct MockMessage: ConvosSDK.RawMessageType {
    var id: String
    var content: String
    var sender: any ConvosSDK.User
    var timestamp: Date
    var replies: [any ConvosSDK.RawMessageType]

    static func message(_ content: String, sender: any ConvosSDK.User) -> MockMessage {
        .init(
            id: UUID().uuidString,
            content: content,
            sender: sender,
            timestamp: Date(),
            replies: []
        )
    }
}

struct MockConversation: ConvosSDK.ConversationType {
    var id: String
    var lastMessage: (any ConvosSDK.RawMessageType)? {
        get async throws {
            nil
        }
    }
    var otherParticipant: (any ConvosSDK.User)?
    var isPinned: Bool
    var isUnread: Bool
    var isRequest: Bool
    var isMuted: Bool
    var timestamp: Date
    var amount: Double?
}

class MockMessagingService: ConvosSDK.MessagingServiceProtocol {
    enum MockMessagingServiceError: Error {
        case unauthorized
    }

    private let currentUser: MockUser? = nil

    private var messagingStateSubject: CurrentValueSubject<ConvosSDK.MessagingServiceState, Never> =
    CurrentValueSubject<ConvosSDK.MessagingServiceState, Never>(.uninitialized)
    private var messagesSubject: CurrentValueSubject<[any ConvosSDK.RawMessageType], Never> =
    CurrentValueSubject<[any ConvosSDK.RawMessageType], Never>([])

    var state: ConvosSDK.MessagingServiceState {
        messagingStateSubject.value
    }

    func start() async throws {
    }

    func stop() {
    }

    func conversations() async throws -> [any ConvosSDK.ConversationType] {
        return []
    }

    func conversationsStream() async -> AsyncThrowingStream<any ConvosSDK.ConversationType, any Error> {
        return .init {
            nil
        }
    }

    func loadInitialMessages() async -> [any ConvosSDK.RawMessageType] {
        return []
    }

    func loadPreviousMessages() async -> [any ConvosSDK.RawMessageType] {
        return []
    }

    func sendMessage(to address: String, content: String) async throws -> [any ConvosSDK.RawMessageType] {
        guard let currentUser else {
            throw MockMessagingServiceError.unauthorized
        }
        messagesSubject.send([MockMessage.message(content, sender: currentUser)])
        return messagesSubject.value
    }

    func messages(for address: String) -> AnyPublisher<[any ConvosSDK.RawMessageType], Never> {
        messagesSubject.eraseToAnyPublisher()
    }

    func messagingStatePublisher() -> AnyPublisher<ConvosSDK.MessagingServiceState, Never> {
        messagingStateSubject.eraseToAnyPublisher()
    }
}
