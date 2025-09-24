import Combine
import Foundation

public protocol SessionManagerProtocol {
    // MARK: Messaging Service
    var messagingService: AnyMessagingService { get }

    // MARK: Session Actions

    func deleteAllData() async throws
    func deleteConversation(conversationId: String) async throws

    // MARK: Factory methods for repositories

    func inviteRepository(for conversationId: String) -> any InviteRepositoryProtocol

    func conversationRepository(for conversationId: String) -> any ConversationRepositoryProtocol

    func messagesRepository(for conversationId: String) -> any MessagesRepositoryProtocol

    func conversationsRepository(for consent: [Consent]) -> any ConversationsRepositoryProtocol
    func conversationsCountRepo(
        for consent: [Consent],
        kinds: [ConversationKind]
    ) -> any ConversationsCountRepositoryProtocol

    // MARK: Notifications

    func shouldDisplayNotification(for conversationId: String) async -> Bool
}
