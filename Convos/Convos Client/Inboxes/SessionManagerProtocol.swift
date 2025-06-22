import Foundation

protocol SessionManagerProtocol {
    var inboxesRepository: any InboxesRepositoryProtocol { get }
    func messagingService(for inboxId: String) throws -> any MessagingServiceProtocol
    func conversationsRepository(for consent: [Consent]) -> any ConversationsRepositoryProtocol
    func conversationsCountRepo(for consent: [Consent]) -> any ConversationsCountRepositoryProtocol
}
