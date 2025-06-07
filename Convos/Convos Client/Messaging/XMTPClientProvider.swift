import Foundation
import XMTPiOS

protocol MessageSender {
    func prepare(text: String) async throws -> String
    func publish() async throws
}

protocol ConversationSender {
    func add(members inboxIds: [String]) async throws
    func remove(members inboxIds: [String]) async throws
    func prepare(text: String) async throws -> String
    func publish() async throws
}

protocol XMTPClientProvider: AnyObject {
    func messageSender(for conversationId: String) async throws -> (any MessageSender)?
    func canMessage(identity: String) async throws -> Bool
    func canMessage(identities: [String]) async throws -> [String: Bool]
    func prepareConversation() async throws -> ConversationSender
    func newConversation(with memberInboxIds: [String],
                         name: String,
                         description: String,
                         imageUrl: String) async throws -> String
    func newConversation(with memberInboxId: String) async throws -> String
    func conversation(with id: String) async throws -> XMTPiOS.Conversation?
    func inboxId(for ethereumAddress: String) async throws -> String?
    func update(consent: Consent, for conversation: Conversation) async throws
}

enum XMTPClientProviderError: Error {
    case conversationNotFound(id: String)
}

extension XMTPiOS.Group: ConversationSender {
    func add(members inboxIds: [String]) async throws {
        _ = try await addMembers(inboxIds: inboxIds)
    }

    func remove(members inboxIds: [String]) async throws {
        _ = try await removeMembers(inboxIds: inboxIds)
    }

    func prepare(text: String) async throws -> String {
        return try await prepareMessage(content: text)
    }

    func publish() async throws {
        try await publishMessages()
    }
}

extension XMTPiOS.Client: XMTPClientProvider {
    func canMessage(identity: String) async throws -> Bool {
        return try await canMessage(
            identity: PublicIdentity(kind: .ethereum, identifier: identity)
        )
    }

    func prepareConversation() async throws -> ConversationSender {
        return try await conversations.newGroupOptimistic()
    }

    func newConversation(with memberInboxIds: [String],
                         name: String,
                         description: String,
                         imageUrl: String) async throws -> String {
        let group = try await conversations.newGroup(
            with: memberInboxIds,
            name: name,
            imageUrl: imageUrl,
            description: description
        )
        return group.id
    }

    func newConversation(with memberInboxId: String) async throws -> String {
        let group = try await conversations.newConversation(
            with: memberInboxId,
            disappearingMessageSettings: nil
        )
        return group.id
    }

    func conversation(with id: String) async throws -> XMTPiOS.Conversation? {
        return try await conversations.findConversation(conversationId: id)
    }

    func canMessage(identities: [String]) async throws -> [String: Bool] {
        return try await canMessage(
            identities: identities.map {
                PublicIdentity(kind: .ethereum, identifier: $0)
            }
        )
    }

    func messageSender(for conversationId: String) async throws -> (any MessageSender)? {
        return try await conversations.findConversation(conversationId: conversationId)
    }

    func inboxId(for ethereumAddress: String) async throws -> String? {
        return try await inboxIdFromIdentity(identity: .init(kind: .ethereum, identifier: ethereumAddress))
    }

    func update(consent: Consent, for conversation: Conversation) async throws {
        guard let foundConversation = try await self.conversation(with: conversation.id) else {
            throw XMTPClientProviderError.conversationNotFound(id: conversation.id)
        }
        try await foundConversation.updateConsentState(state: consent.consentState)
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
