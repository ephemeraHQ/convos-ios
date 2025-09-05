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
        let trimmedInviteCode = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)

        return try await databaseReader.read { db in
            guard let existingInvite = try DBInvite.fetchOne(db, key: trimmedInviteCode) else {
                return nil
            }
            guard let existingConversation = try DBConversation.fetchOne(db, key: existingInvite.conversationId) else {
                return nil
            }
            return existingConversation.id
        }
    }
}
