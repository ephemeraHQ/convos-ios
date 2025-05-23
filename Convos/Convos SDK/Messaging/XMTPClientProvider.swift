import Foundation
import XMTPiOS

protocol MessageSender {
    func send(text: String) async throws -> String
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
    func send(text: String) async throws -> String {
        return try await send(text: text, options: nil)
    }
}
