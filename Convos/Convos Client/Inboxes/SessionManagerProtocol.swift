import Combine
import Foundation

protocol SessionManagerProtocol {
    var inboxesRepository: any InboxesRepositoryProtocol { get }

    var authState: AnyPublisher<AuthServiceState, Never> { get }

    func prepare() async throws
    func addAccount() async throws
    func messagingService(for inboxId: String) -> AnyMessagingService
    func conversationsRepository(for consent: [Consent]) -> any ConversationsRepositoryProtocol
    func conversationsCountRepo(for consent: [Consent]) -> any ConversationsCountRepositoryProtocol
}
