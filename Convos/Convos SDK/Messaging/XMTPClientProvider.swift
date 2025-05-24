import Foundation
import XMTPiOS

protocol MessageSender {
    func prepare(text: String) async throws -> String
    func publish() async throws
}

protocol XMTPClientProvider: AnyObject {
    func messageSender(for conversationId: String) async throws -> (any MessageSender)?
}

extension XMTPiOS.Client: XMTPClientProvider {
    func messageSender(for conversationId: String) async throws -> (any MessageSender)? {
        return try await conversations.findConversation(conversationId: conversationId)
    }
}

extension XMTPiOS.Conversation: MessageSender {
    func prepare(text: String) async throws -> String {
        return try await prepareMessage(content: text)
    }

    func publish() async throws {
        try await publishMessages()
    }
}
