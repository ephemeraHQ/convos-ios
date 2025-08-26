import Foundation
import XMTPiOS

public protocol MessageSender {
    func prepare(text: String) async throws -> String
    func publish() async throws
}

public protocol ConversationSender {
    var id: String { get }
    func add(members inboxIds: [String]) async throws
    func remove(members inboxIds: [String]) async throws
    func prepare(text: String) async throws -> String
    func publish() async throws
}

public protocol ConversationsProvider: Actor {
    func listGroups(
        createdAfter: Date?,
        createdBefore: Date?,
        limit: Int?,
        consentStates: [ConsentState]?
    ) throws -> [XMTPiOS.Group]

    func list(
        createdAfter: Date?,
        createdBefore: Date?,
        limit: Int?,
        consentStates: [ConsentState]?
    ) async throws -> [XMTPiOS.Conversation]

    func stream(
        type: ConversationFilterType,
        onClose: (() -> Void)?
    ) -> AsyncThrowingStream<XMTPiOS.Conversation, Error>

    func findConversation(conversationId: String) async throws
    -> XMTPiOS.Conversation?

    func syncAllConversations(consentStates: [XMTPiOS.ConsentState]?) async throws -> UInt32
    func streamAllMessages(
        type: XMTPiOS.ConversationFilterType,
        consentStates: [XMTPiOS.ConsentState]?,
        onClose: (() -> Void)?
    ) -> AsyncThrowingStream<XMTPiOS.DecodedMessage, Error>
}

public protocol XMTPClientProvider: AnyObject {
    var installationId: String { get }
    var inboxId: String { get }
    var conversationsProvider: ConversationsProvider { get }
    func signWithInstallationKey(message: String) throws -> Data
    func messageSender(for conversationId: String) async throws -> (any MessageSender)?
    func canMessage(identity: String) async throws -> Bool
    func canMessage(identities: [String]) async throws -> [String: Bool]
    func prepareConversation() async throws -> ConversationSender
    func newConversation(with memberInboxIds: [String],
                         name: String,
                         description: String,
                         imageUrl: String) async throws -> String
    func newConversation(with memberInboxId: String) async throws -> (any MessageSender)
    func conversation(with id: String) async throws -> XMTPiOS.Conversation?
    func inboxId(for ethereumAddress: String) async throws -> String?
    func update(consent: Consent, for conversationId: String) async throws
    func revokeInstallations(
        signingKey: SigningKey, installationIds: [String]
    ) async throws
    func deleteLocalDatabase() throws
}

enum XMTPClientProviderError: Error {
    case conversationNotFound(id: String)
}

extension XMTPiOS.Group: ConversationSender {
    public func add(members inboxIds: [String]) async throws {
        _ = try await addMembers(inboxIds: inboxIds)
    }

    public func remove(members inboxIds: [String]) async throws {
        _ = try await removeMembers(inboxIds: inboxIds)
    }

    public func prepare(text: String) async throws -> String {
        return try await prepareMessage(content: text)
    }

    public func publish() async throws {
        try await publishMessages()
    }
}

extension XMTPiOS.Conversations: ConversationsProvider {
}

extension XMTPiOS.Client: XMTPClientProvider {
    public var conversationsProvider: any ConversationsProvider {
        conversations
    }

    public var installationId: String {
        installationID
    }

    public var inboxId: String {
        inboxID
    }

    public func canMessage(identity: String) async throws -> Bool {
        return try await canMessage(
            identity: PublicIdentity(kind: .ethereum, identifier: identity)
        )
    }

    public func prepareConversation() async throws -> ConversationSender {
        return try await conversations.newGroupOptimistic()
    }

    public func newConversation(with memberInboxIds: [String],
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

    public func newConversation(with memberInboxId: String) async throws -> (any MessageSender) {
        let group = try await conversations.newConversation(
            with: memberInboxId,
            disappearingMessageSettings: nil
        )
        return group
    }

    public func conversation(with id: String) async throws -> XMTPiOS.Conversation? {
        return try await conversations.findConversation(conversationId: id)
    }

    public func canMessage(identities: [String]) async throws -> [String: Bool] {
        return try await canMessage(
            identities: identities.map {
                PublicIdentity(kind: .ethereum, identifier: $0)
            }
        )
    }

    public func messageSender(for conversationId: String) async throws -> (any MessageSender)? {
        return try await conversations.findConversation(conversationId: conversationId)
    }

    public func inboxId(for ethereumAddress: String) async throws -> String? {
        return try await inboxIdFromIdentity(identity: .init(kind: .ethereum, identifier: ethereumAddress))
    }

    public func update(consent: Consent, for conversationId: String) async throws {
        guard let foundConversation = try await self.conversation(with: conversationId) else {
            throw XMTPClientProviderError.conversationNotFound(id: conversationId)
        }
        try await foundConversation.updateConsentState(state: consent.consentState)
    }
}

extension XMTPiOS.Conversation: MessageSender {
    public func prepare(text: String) async throws -> String {
        return try await prepareMessage(content: text)
    }

    public func publish() async throws {
        try await publishMessages()
    }
}
