import Combine
import Foundation

protocol MessagingServiceProtocol {
    func profileSearchRepository() -> any ProfileSearchRepositoryProtocol

    func draftConversationComposer() -> any DraftConversationComposerProtocol
    func conversationsRepository(for consent: [Consent]) -> any ConversationsRepositoryProtocol
    func conversationRepository(for conversationId: String) -> any ConversationRepositoryProtocol
    func conversationConsentWriter() -> any ConversationConsentWriterProtocol
    func conversationsCountRepo(for consent: [Consent]) -> any ConversationsCountRepositoryProtocol
    func conversationLocalStateWriter() -> any ConversationLocalStateWriterProtocol

    func messagesRepository(for conversationId: String) -> any MessagesRepositoryProtocol
    func messageWriter(for conversationId: String) -> any OutgoingMessageWriterProtocol
}
