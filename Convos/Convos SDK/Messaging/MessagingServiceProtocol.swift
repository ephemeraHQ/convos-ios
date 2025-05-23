import Combine
import Foundation

extension ConvosSDK {
    protocol MessagingServiceProtocol {
        var state: MessagingServiceState { get }
        var clientPublisher: AnyPublisher<(any XMTPClientProvider)?, Never> { get }

        func start() async throws
        func stop() async

        func profileSearchRepository() -> any ProfileSearchRepositoryProtocol

        func messagesRepository(for conversationId: String) -> any MessagesRepositoryProtocol
        func messageWriter(for conversationId: String) -> any OutgoingMessageWriterProtocol

        func messagingStatePublisher() -> AnyPublisher<MessagingServiceState, Never>
    }

    enum MessagingServiceState {
        case uninitialized
        case initializing
        case authorizing
        case ready
        case stopping
        case error(Error)

        var isReady: Bool {
            switch self {
            case .ready:
                return true
            default:
                return false
            }
        }
    }
}
