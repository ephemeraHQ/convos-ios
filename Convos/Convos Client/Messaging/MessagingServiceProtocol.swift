import Combine
import Foundation

protocol MessagingServiceProtocol {
    var state: MessagingServiceState { get }
    var clientPublisher: AnyPublisher<(any XMTPClientProvider)?, Never> { get }

    var messagingStatePublisher: AnyPublisher<MessagingServiceState, Never> { get }

    func start() async throws
    func stop() async

    func userRepository() -> any UserRepositoryProtocol

    func profileSearchRepository() -> any ProfileSearchRepositoryProtocol

    func draftConversationComposer() -> any DraftConversationComposerProtocol
    func conversationsRepository(for consent: [Consent]) -> any ConversationsRepositoryProtocol
    func conversationRepository(for conversationId: String) -> any ConversationRepositoryProtocol
    func conversationConsentWriter() -> any ConversationConsentWriterProtocol
    func conversationsCountRepo(for consent: [Consent]) -> any ConversationsCountRepositoryProtocol
    func conversationLocalStateWriter() -> any ConversationLocalStateWriterProtocol

    func messagesRepository(for conversationId: String) -> any MessagesRepositoryProtocol
    func messageWriter(for conversationId: String) -> any OutgoingMessageWriterProtocol

    func groupMetadataWriter() -> any GroupMetadataWriterProtocol
    func groupPermissionsRepository() -> any GroupPermissionsRepositoryProtocol
}

enum MessagingServiceState: Equatable {
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

    static func == (lhs: MessagingServiceState, rhs: MessagingServiceState) -> Bool {
        switch (lhs, rhs) {
        case (.uninitialized, .uninitialized),
            (.initializing, .initializing),
            (.authorizing, .authorizing),
            (.ready, .ready),
            (.stopping, .stopping):
            return true
        case (.error, .error):
            return true
        default:
            return false
        }
    }
}
