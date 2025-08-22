import Combine
import Foundation

public struct AddAccountResultType {
    public let providerId: String
    public let messagingService: AnyMessagingService
}

public protocol SessionManagerProtocol {
    func prepare() throws
    func addAccount() throws -> AddAccountResultType
    func deleteAccount(inboxId: String) throws
    func deleteAccount(providerId: String) throws
    func deleteAllAccounts() throws
    func messagingService(for inboxId: String) -> AnyMessagingService
    func conversationsRepository(for consent: [Consent]) -> any ConversationsRepositoryProtocol
    func conversationsCountRepo(
        for consent: [Consent],
        kinds: [ConversationKind]
    ) -> any ConversationsCountRepositoryProtocol
}
