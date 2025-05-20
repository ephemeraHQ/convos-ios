import Combine
import Foundation

extension ConvosSDK {
    protocol User {
        var id: String { get }
        var profile: ConvosSDK.Profile { get }
    }

    protocol Profile {
        var name: String { get }
        var username: String { get }
        var avatarURL: URL? { get }
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
        var timestamp: Date { get }
    }

    protocol MessagingServiceProtocol {
        var state: MessagingServiceState { get }

        func start() async throws
        func stop() async

        func profileSearchRepository() -> any ProfileSearchRepositoryProtocol

        func sendMessage(to address: String, content: String) async throws -> [any RawMessageType]
        func messages(for address: String) -> AnyPublisher<[any RawMessageType], Never>
        func messagingStatePublisher() -> AnyPublisher<MessagingServiceState, Never>
        func loadInitialMessages() async -> [any RawMessageType]
        func loadPreviousMessages() async -> [any RawMessageType]
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
