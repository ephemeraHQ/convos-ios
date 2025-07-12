import Combine
import Foundation

protocol MessagingServiceProtocol {
    var inboxReadyPublisher: InboxReadyResultPublisher { get }

    func profileSearchRepository() -> any ProfileSearchRepositoryProtocol

    func draftConversationComposer() -> any DraftConversationComposerProtocol
    func conversationsRepository(for consent: [Consent]) -> any ConversationsRepositoryProtocol
    func conversationRepository(for conversationId: String) -> any ConversationRepositoryProtocol
    func conversationConsentWriter() -> any ConversationConsentWriterProtocol
    func conversationsCountRepo(for consent: [Consent]) -> any ConversationsCountRepositoryProtocol
    func conversationLocalStateWriter() -> any ConversationLocalStateWriterProtocol

    func messagesRepository(for conversationId: String) -> any MessagesRepositoryProtocol
    func messageWriter(for conversationId: String) -> any OutgoingMessageWriterProtocol

    func groupMetadataWriter() -> any GroupMetadataWriterProtocol
    func groupPermissionsRepository() -> any GroupPermissionsRepositoryProtocol

    func uploadImage(data: Data, filename: String) async throws -> String
    func uploadImageAndExecute(
        data: Data,
        filename: String,
        afterUpload: @escaping (String) async throws -> Void
    ) async throws -> String
}
