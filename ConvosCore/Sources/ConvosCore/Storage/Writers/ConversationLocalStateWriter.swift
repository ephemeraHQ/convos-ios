import Foundation
import GRDB

public protocol ConversationLocalStateWriterProtocol {
    func setUnread(_ isUnread: Bool, for conversationId: String) async throws
    func setPinned(_ isPinned: Bool, for conversationId: String) async throws
    func setMuted(_ isMuted: Bool, for conversationId: String) async throws
}

class ConversationLocalStateWriter: ConversationLocalStateWriterProtocol {
    private let databaseWriter: any DatabaseWriter

    init(databaseWriter: any DatabaseWriter) {
        self.databaseWriter = databaseWriter
    }

    func setUnread(_ isUnread: Bool, for conversationId: String) async throws {
        try await updateLocalState(for: conversationId) { state in
            state.with(isUnread: isUnread)
        }
    }

    func setPinned(_ isPinned: Bool, for conversationId: String) async throws {
        try await updateLocalState(for: conversationId) { state in
            state.with(isPinned: isPinned)
        }
    }

    func setMuted(_ isMuted: Bool, for conversationId: String) async throws {
        try await updateLocalState(for: conversationId) { state in
            state.with(isMuted: isMuted)
        }
    }

    private func updateLocalState(
        for conversationId: String,
        _ update: @escaping (ConversationLocalState) -> ConversationLocalState
    ) async throws {
        try await databaseWriter.write { db in
            guard try DBConversation.fetchOne(db, key: conversationId) != nil else {
                throw ConversationLocalStateWriterError.conversationNotFound
            }

            let current = try ConversationLocalState
                .filter(Column("conversationId") == conversationId)
                .fetchOne(db)
                ?? ConversationLocalState(
                    conversationId: conversationId,
                    isPinned: false,
                    isUnread: false,
                    isUnreadUpdatedAt: Date(),
                    isMuted: false
                )
            let updated = update(current)
            try updated.save(db)
        }
    }
}

enum ConversationLocalStateWriterError: Error {
    case conversationNotFound
}
