import Combine
import Foundation

public protocol SessionManagerProtocol {
    func addInbox() async throws -> AnyMessagingService
    func deleteInbox(inboxId: String) throws
    func deleteInbox(for messagingService: AnyMessagingService) throws
    func deleteAllInboxes() throws
    func messagingService(for inboxId: String) -> AnyMessagingService
    func conversationsRepository(for consent: [Consent]) -> any ConversationsRepositoryProtocol
    func conversationsCountRepo(
        for consent: [Consent],
        kinds: [ConversationKind]
    ) -> any ConversationsCountRepositoryProtocol
}
