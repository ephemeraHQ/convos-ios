import Foundation
import GRDB

/// Utility for looking up existing conversations by invite code
public struct ConversationLookupUtility {
    private let inboxStateManager: any InboxStateManagerProtocol
    private let databaseReader: any DatabaseReader

    public init(inboxStateManager: any InboxStateManagerProtocol,
                databaseReader: any DatabaseReader) {
        self.inboxStateManager = inboxStateManager
        self.databaseReader = databaseReader
    }

    /// Finds an existing conversation ID for the given invite code
    /// - Parameter inviteCode: The invite code to look up
    /// - Returns: The conversation ID if found, nil otherwise
    public func findExistingConversationForInviteCode(_ inviteCode: String) async throws -> String? {
        let trimmedInviteCode = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)

        let conversationIdByInviteCode: String? = try await databaseReader.read { db in
            guard let existingInvite = try DBInvite.fetchOne(db, key: trimmedInviteCode) else {
                return nil
            }
            guard let existingConversation = try DBConversation.fetchOne(db, key: existingInvite.conversationId) else {
                return nil
            }
            return existingConversation.id
        }

        if let conversationIdByInviteCode {
            return conversationIdByInviteCode
        } else {
            // we might have joined the conversation already but have tapped a different invite code
            // than what we have locally, so lookup the conversation ID in the backend
            let inboxReady = try await inboxStateManager.waitForInboxReadyResult()
            let inviteDetails = try? await inboxReady.apiClient.inviteDetailsWithGroup(trimmedInviteCode)
            let conversationId = inviteDetails?.groupId
            return try await databaseReader.read { db in
                let existingConversation = try DBConversation.fetchOne(db, key: conversationId)
                return existingConversation?.id
            }
        }
    }
}
