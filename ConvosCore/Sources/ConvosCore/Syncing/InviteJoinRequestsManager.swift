import Foundation
import GRDB
import XMTPiOS

public enum InviteJoinRequestError: Error {
    case invalidSignature
    case conversationNotFound(String)
    case invalidConversationType
    case missingTextContent
    case invalidInviteFormat
}

protocol InviteJoinRequestsManagerProtocol {
    func start(with client: AnyClientProvider,
               apiClient: any ConvosAPIClientProtocol)
    func stop()
    func processJoinRequest(
        message: XMTPiOS.DecodedMessage,
        client: AnyClientProvider
    ) async throws -> String?
}

class InviteJoinRequestsManager: InviteJoinRequestsManagerProtocol {
    private let identityStore: any KeychainIdentityStoreProtocol
    private let databaseReader: any DatabaseReader

    private var streamMessagesTask: Task<Void, Never>?

    init(identityStore: any KeychainIdentityStoreProtocol,
         databaseReader: any DatabaseReader) {
        self.identityStore = identityStore
        self.databaseReader = databaseReader
    }

    deinit {
        streamMessagesTask?.cancel()
        streamMessagesTask = nil
    }

    /// Process a message as a potential join request
    /// - Parameters:
    ///   - message: The decoded message to process
    ///   - client: The XMTP client provider
    /// - Returns: The conversation ID that the sender was added to, or nil if not a valid join request
    func processJoinRequest(
        message: XMTPiOS.DecodedMessage,
        client: AnyClientProvider
    ) async throws -> String? {
        let dbMessage = try message.dbRepresentation()
        guard let text = dbMessage.text else {
            Logger.info("Message has no text content, not a join request")
            throw InviteJoinRequestError.missingTextContent
        }

        // Try to parse as signed invite
        let signedInvite: SignedInvite
        do {
            signedInvite = try SignedInvite.fromURLSafeSlug(text)
        } catch {
            Logger.info("Message text is not a valid signed invite format")
            throw InviteJoinRequestError.invalidInviteFormat
        }

        // @jarodl do more validation here, if someone is sending bogus invites, block the inbox id

        let identity = try await identityStore.identity()
        let publicKey = identity.keys.privateKey.publicKey.secp256K1Uncompressed.bytes

        let verifiedSignature = try signedInvite.verify(with: publicKey)
        guard verifiedSignature else {
            Logger.error("Failed verifying signature for invite, not a valid join request")
            throw InviteJoinRequestError.invalidSignature
        }

        let privateKey: Data = identity.keys.privateKey.secp256K1.bytes
        let conversationToken = signedInvite.payload.conversationToken
        let conversationId = try InviteConversationToken.decodeConversationToken(
            conversationToken,
            creatorInboxId: client.inboxId,
            secp256k1PrivateKey: privateKey
        )

        guard let conversation = try await client.conversationsProvider.findConversation(
            conversationId: conversationId
        ) else {
            Logger.warning("Conversation \(conversationId) not found on XMTP")
            throw InviteJoinRequestError.conversationNotFound(conversationId)
        }

        switch conversation {
        case .group(let group):
            Logger.info("Adding \(message.senderInboxId) to group \(group.id)...")
            try await group.add(members: [message.senderInboxId])
            // Optionally store the conversation update
            // Logger.info("Storing conversation with id: \(conversation.id)")
            // try await conversationWriter.store(conversation: conversation)
            return group.id
        case .dm:
            Logger.warning("Expected Group but found DM, ignoring invite join request...")
            throw InviteJoinRequestError.invalidConversationType
        }
    }

    func start(with client: AnyClientProvider,
               apiClient: any ConvosAPIClientProtocol) {
        let inboxId = client.inboxId
        streamMessagesTask = Task { [weak self, client] in
            do {
                Logger.info("Started streaming messages for invite join requests...")
                for try await message in client.conversationsProvider
                    .streamAllMessages(
                        type: .dms,
                        consentStates: [.unknown, .allowed],
                        onClose: {
                            Logger.warning("Closing streamAllMessages...")
                        }
                    ).filter({ $0.senderInboxId != inboxId }) {
                    guard let self else { return }
                    do {
                        Logger.info("Processing potential join request from \(message.senderInboxId)")
                        if let conversationId = try await self.processJoinRequest(
                            message: message,
                            client: client
                        ) {
                            Logger.info("Successfully added \(message.senderInboxId) to conversation \(conversationId)")
                        }
                    } catch InviteJoinRequestError.missingTextContent {
                        // Silently skip - not a join request
                    } catch InviteJoinRequestError.invalidInviteFormat {
                        // Silently skip - not a join request
                    } catch InviteJoinRequestError.invalidSignature {
                        Logger.error("Invalid signature in join request from \(message.senderInboxId)")
                    } catch InviteJoinRequestError.conversationNotFound(let id) {
                        Logger.error("Conversation \(id) not found for join request from \(message.senderInboxId)")
                    } catch InviteJoinRequestError.invalidConversationType {
                        Logger.error("Join request targets a DM instead of a group")
                    } catch {
                        Logger.error("Error processing join request: \(error.localizedDescription)")
                    }
                }
            } catch {
                Logger.error("Error streaming all messages: \(error)")
            }
        }
    }

    func stop() {
        streamMessagesTask?.cancel()
    }
}
