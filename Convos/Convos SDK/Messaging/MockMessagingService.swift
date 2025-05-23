import Combine
import Foundation

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
    var clientPublisher: AnyPublisher<(any XMTPClientProvider)?, Never> {
        Just(nil).eraseToAnyPublisher()
    }

    var state: ConvosSDK.MessagingServiceState {
        messagingStateSubject.value
    }

    func start() async throws {
    }

    func stop() {
    }

    func profileSearchRepository() -> any ProfileSearchRepositoryProtocol {
        MockProfileSearchRepository()
    }

    func messagesRepository(for conversationId: String) -> any MessagesRepositoryProtocol {
        MockMessagesRepository()
    }

    func messageWriter(for conversationId: String) -> any OutgoingMessageWriterProtocol {
        MockOutgoingMessageWriter()
    }

    func messages(for address: String) -> AnyPublisher<[any ConvosSDK.RawMessageType], Never> {
        messagesSubject.eraseToAnyPublisher()
    }

    func messagingStatePublisher() -> AnyPublisher<ConvosSDK.MessagingServiceState, Never> {
        messagingStateSubject.eraseToAnyPublisher()
    }
}
