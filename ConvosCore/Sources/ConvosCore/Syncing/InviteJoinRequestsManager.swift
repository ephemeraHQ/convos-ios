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

    // Track last successful sync
    private var lastSynced: Date? {
        get {
            let timestamp = UserDefaults.standard.double(forKey: "org.convos.InviteJoinRequestsManager.lastSynced")
            return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "org.convos.InviteJoinRequestsManager.lastSynced")
        }
    }

    init(identityStore: any KeychainIdentityStoreProtocol,
         databaseReader: any DatabaseReader) {
        self.identityStore = identityStore
        self.databaseReader = databaseReader
    }

    deinit {
        streamMessagesTask?.cancel()
        streamMessagesTask = nil
    }

    // MARK: - Processing

    /// Process a message as a potential join request, with error handling
    /// - Parameters:
    ///   - message: The decoded message to process
    ///   - client: The XMTP client provider
    private func processJoinRequestSafely(
        message: XMTPiOS.DecodedMessage,
        client: AnyClientProvider
    ) async {
        do {
            if let conversationId = try await processJoinRequest(
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
            Logger.error("Error processing join request: \(error)")
        }
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

        let inboxId = signedInvite.payload.creatorInboxID
        let identity = try await identityStore.identity(for: inboxId)
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
        ), try conversation.consentState() == .allowed else {
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

    // MARK: - Sync Operations

    /// Sync all DMs to catch up on any missed join requests
    private func syncAllDms(client: AnyClientProvider) async {
        do {
            Logger.info("Syncing all DMs for join requests...")

            let inboxId = client.inboxId
            let syncStartTime = Date()

            // List all DMs with consent states .unknown
            _ = try await client.conversationsProvider.syncAllConversations(consentStates: [.unknown])
            let dms = try client.conversationsProvider.listDms(
                createdAfter: lastSynced,
                createdBefore: nil,
                limit: 250, // @jarodl max group size for now
                consentStates: [.unknown]
            )

            Logger.info("Found \(dms.count) DMs to check for join requests")

            // Process each DM in parallel
            await withTaskGroup(of: Void.self) { group in
                for dm in dms {
                    group.addTask { [weak self] in
                        do {
                            guard let self else { return }
                            let messages = try await dm.messages(afterNs: nil)
                                .filter { message in
                                    guard let encodedContentType = try? message.encodedContent.type else {
                                        return false
                                    }

                                    switch encodedContentType {
                                    case ContentTypeText:
                                        return message.senderInboxId != inboxId
                                    default:
                                        return false
                                    }
                                }
                            Logger.info("Found \(messages.count) messages as possible join requests")
                            for message in messages {
                                // Try to process as join request
                                await self.processJoinRequestSafely(
                                    message: message,
                                    client: client
                                )
                            }
                        } catch {
                            Logger.error("Error processing messages as join requests: \(error.localizedDescription)")
                        }
                    }
                }
            }

            // Update last synced timestamp after successful sync
            lastSynced = syncStartTime
            Logger.info("Completed DM sync for join requests")
        } catch {
            Logger.error("Error syncing DMs: \(error)")
        }
    }

    func start(with client: AnyClientProvider,
               apiClient: any ConvosAPIClientProtocol) {
        let inboxId = client.inboxId
        streamMessagesTask = Task { [weak self, client] in
            guard let self else { return }

            // Initial sync of all DMs to catch up on missed join requests
            await self.syncAllDms(client: client)

            do {
                Logger.info("Started streaming messages for invite join requests...")
                for try await message in client.conversationsProvider
                    .streamAllMessages(
                        type: .dms,
                        consentStates: [.unknown],
                        onClose: {
                            Logger.warning("Closing streamAllMessages...")
                        }
                    ).filter({ $0.senderInboxId != inboxId }) {
                    Logger.info("Processing potential join request from \(message.senderInboxId)")
                    await self.processJoinRequestSafely(
                        message: message,
                        client: client
                    )
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
