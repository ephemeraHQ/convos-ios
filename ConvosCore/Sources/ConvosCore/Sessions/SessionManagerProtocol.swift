import Combine
import Foundation

public protocol SessionManagerProtocol: AnyObject {
    // MARK: Inbox Management

    func addInbox() async throws -> AnyMessagingService
    func deleteInbox(inboxId: String) async throws
    func deleteInbox(for messagingService: AnyMessagingService) async throws
    func deleteAllInboxes() async throws

    // MARK: Messaging Services

    func messagingService(for inboxId: String) -> AnyMessagingService

    // MARK: Factory methods for repositories

    func inviteRepository(for conversationId: String) -> any InviteRepositoryProtocol

    func conversationRepository(
        for conversationId: String,
        inboxId: String
    ) -> any ConversationRepositoryProtocol

    func messagesRepository(for conversationId: String) -> any MessagesRepositoryProtocol

    func conversationsRepository(for consent: [Consent]) -> any ConversationsRepositoryProtocol
    func conversationsCountRepo(
        for consent: [Consent],
        kinds: [ConversationKind]
    ) -> any ConversationsCountRepositoryProtocol

    // MARK: Notifications

    func shouldDisplayNotification(for conversationId: String) async -> Bool

    func inboxId(for conversationId: String) async -> String?
}
