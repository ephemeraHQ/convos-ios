import Combine
import Foundation

public protocol SessionManagerProtocol {
    func addInbox() async throws -> AnyMessagingService
    func deleteInbox(inboxId: String) async throws
    func deleteInbox(for messagingService: AnyMessagingService) async throws
    func deleteAllInboxes() async throws
    func messagingService(for inboxId: String) async -> AnyMessagingService
    func conversationsRepository(for consent: [Consent]) -> any ConversationsRepositoryProtocol
    func conversationsCountRepo(
        for consent: [Consent],
        kinds: [ConversationKind]
    ) -> any ConversationsCountRepositoryProtocol
    func shouldDisplayNotification(for conversationId: String) async -> Bool
}
