import Combine
import Foundation

struct AddAccountResultType {
    var providerId: String
    var messagingService: AnyMessagingService
}

protocol SessionManagerProtocol {
    var inboxesRepository: any InboxesRepositoryProtocol { get }

    var authState: AnyPublisher<AuthServiceState, Never> { get }

    func prepare() throws
    func addAccount() throws -> AddAccountResultType
    func deleteAccount(with providerId: String) throws
    func deleteAllAccounts() throws
    func messagingService(for inboxId: String) -> AnyMessagingService
    func conversationsRepository(for consent: [Consent]) -> any ConversationsRepositoryProtocol
    func conversationsCountRepo(for consent: [Consent]) -> any ConversationsCountRepositoryProtocol
}
