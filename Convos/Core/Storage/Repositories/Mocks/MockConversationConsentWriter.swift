import Foundation

class MockConversationConsentWriter: ConversationConsentWriterProtocol {
    func deleteAll() async throws {
    }

    func join(conversation: Conversation) async throws {
    }

    func delete(conversation: Conversation) async throws {
    }
}
