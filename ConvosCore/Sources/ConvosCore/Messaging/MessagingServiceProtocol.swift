import Combine
import Foundation

public protocol MessagingServiceProtocol: AnyObject {
    var identifier: String { get }

    func stopAndDelete()
    func stopAndDelete() async

    func registerForPushNotifications() async

    func myProfileRepository() -> any MyProfileRepositoryProtocol
    func myProfileWriter() -> any MyProfileWriterProtocol

    func draftConversationComposer() -> any DraftConversationComposerProtocol

    func inviteRepository(for conversationId: String) -> any InviteRepositoryProtocol

    func conversationsRepository(for consent: [Consent]) -> any ConversationsRepositoryProtocol
    func conversationRepository(for conversationId: String) -> any ConversationRepositoryProtocol
    func conversationConsentWriter() -> any ConversationConsentWriterProtocol
    func conversationsCountRepo(
        for consent: [Consent],
        kinds: [ConversationKind]
    ) -> any ConversationsCountRepositoryProtocol
    func conversationLocalStateWriter() -> any ConversationLocalStateWriterProtocol

    func messagesRepository(for conversationId: String) -> any MessagesRepositoryProtocol
    func messageWriter(for conversationId: String) -> any OutgoingMessageWriterProtocol

    func groupMetadataWriter() -> any ConversationMetadataWriterProtocol
    func groupPermissionsRepository() -> any GroupPermissionsRepositoryProtocol

    func uploadImage(data: Data, filename: String) async throws -> String
    func uploadImageAndExecute(
        data: Data,
        filename: String,
        afterUpload: @escaping (String) async throws -> Void
    ) async throws -> String
}
