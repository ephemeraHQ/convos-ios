import Combine
import Foundation

protocol SessionManagerProtocol {
    var inboxesRepository: any InboxesRepositoryProtocol { get }

    func messagingService(for inboxId: String) -> AnyMessagingService
    func conversationsRepository(for consent: [Consent]) -> any ConversationsRepositoryProtocol
    func conversationsCountRepo(for consent: [Consent]) -> any ConversationsCountRepositoryProtocol
}
