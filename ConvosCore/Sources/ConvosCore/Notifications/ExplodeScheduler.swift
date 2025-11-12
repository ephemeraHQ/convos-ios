import Foundation
import GRDB

public actor ExplodeScheduler {
    private let databaseWriter: any DatabaseWriter

    public init(databaseWriter: any DatabaseWriter) {
        self.databaseWriter = databaseWriter
    }

    public func scheduleIfNeeded(
        conversationId: String,
        conversationName: String?,
        inboxId: String,
        clientId: String,
        expiresAt: Date
    ) async throws {
        let conversationState = try await databaseWriter.read { db in
            guard let conversation = try DBConversation.filter(key: conversationId).fetchOne(db) else {
                return (exists: false, scheduled: false)
            }
            return (exists: true, scheduled: conversation.scheduledExplode)
        }

        guard conversationState.exists else {
            Log.info("Conversation \(conversationId) no longer exists, skipping explosion scheduling")
            return
        }

        guard !conversationState.scheduled else {
            Log.info("Explosion already scheduled for \(conversationId), skipping duplicate")
            return
        }

        let now = Date()
        let timeUntilExplosion = expiresAt.timeIntervalSince(now)

        Log.info("Scheduling explosion for \(conversationId) at \(expiresAt) (in \(timeUntilExplosion) seconds)")

        try await ExplodeNotificationManager.scheduleExplodeNotification(
            conversationId: conversationId,
            conversationName: conversationName,
            inboxId: inboxId,
            clientId: clientId,
            expiresAt: expiresAt
        )

        try await databaseWriter.write { db in
            guard var conversation = try DBConversation.fetchOne(db, key: conversationId) else {
                Log.warning("Conversation \(conversationId) not found when marking explosion as scheduled")
                return
            }
            conversation.scheduledExplode = true
            try conversation.update(db)
        }

        Log.info("Successfully scheduled and marked explosion for \(conversationId)")
    }

    public func cancelScheduled(conversationId: String) async throws {
        ExplodeNotificationManager.cancelExplodeNotification(for: conversationId)

        try await databaseWriter.write { db in
            guard var conversation = try DBConversation.fetchOne(db, key: conversationId) else {
                return
            }
            conversation.scheduledExplode = false
            try conversation.update(db)
        }

        Log.info("Cancelled scheduled explosion for \(conversationId)")
    }
}
