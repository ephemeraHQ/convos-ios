import Foundation
import GRDB

/// Utility for looking up existing conversations by invite code
public struct ConversationLookupUtility {
    private let databaseReader: any DatabaseReader

    public init(databaseReader: any DatabaseReader) {
        self.databaseReader = databaseReader
    }

    /// Finds an existing conversation ID for the given invite code
    /// - Parameter inviteCode: The invite code to look up
    /// - Returns: The conversation ID if found, nil otherwise
    public func findExistingConversationForInviteCode(_ inviteCode: String) async throws -> String? {
        let existingInvite = try await databaseReader.read { db in
            try DBInvite.fetchOne(db, key: inviteCode)
        }

        guard let existingInvite else { return nil }

        let existingConversation = try await databaseReader.read { db in
            try DBConversation.fetchOne(db, key: existingInvite.conversationId)
        }

        return existingConversation?.id
    }
}
