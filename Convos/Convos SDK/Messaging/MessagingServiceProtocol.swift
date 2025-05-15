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
