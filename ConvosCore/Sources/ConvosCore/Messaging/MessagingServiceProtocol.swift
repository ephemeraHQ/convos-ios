import Combine
import Foundation

public protocol MessagingServiceProtocol: AnyObject {
    var inboxStateManager: any InboxStateManagerProtocol { get }

    func reset() async

    func registerForPushNotifications() async

    func myProfileWriter() -> any MyProfileWriterProtocol

    func conversationStateManager() -> any ConversationStateManagerProtocol

    func conversationConsentWriter() -> any ConversationConsentWriterProtocol
    func conversationLocalStateWriter() -> any ConversationLocalStateWriterProtocol

    func messageWriter(for conversationId: String) -> any OutgoingMessageWriterProtocol

    func conversationMetadataWriter() -> any ConversationMetadataWriterProtocol
    func conversationPermissionsRepository() -> any ConversationPermissionsRepositoryProtocol

    func uploadImage(data: Data, filename: String) async throws -> String
    func uploadImageAndExecute(
        data: Data,
        filename: String,
        afterUpload: @escaping (String) async throws -> Void
    ) async throws -> String
}
