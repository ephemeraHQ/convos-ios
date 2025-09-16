import Combine
import Foundation

public protocol MessagingServiceProtocol: AnyObject {
    func stop()
    func stopAndDelete()
    func stopAndDelete() async

    func registerForPushNotifications() async

    func myProfileRepository() -> any MyProfileRepositoryProtocol
    func myProfileWriter() -> any MyProfileWriterProtocol

    func draftConversationComposer() -> any DraftConversationComposerProtocol

    func conversationConsentWriter() -> any ConversationConsentWriterProtocol
    func conversationLocalStateWriter() -> any ConversationLocalStateWriterProtocol

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
