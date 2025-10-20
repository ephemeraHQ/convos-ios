import Foundation
import GRDB
import XMTPiOS

public enum InviteJoinRequestError: Error {
    case invalidSignature
    case conversationNotFound(String)
    case invalidConversationType
    case missingTextContent
    case invalidInviteFormat
    case expired
    case expiredConversation
}

public struct JoinRequestResult {
    public let conversationId: String
    public let conversationName: String?
}

protocol InviteJoinRequestsManagerProtocol {
    func processJoinRequest(
        message: XMTPiOS.DecodedMessage,
        client: AnyClientProvider
    ) async throws -> JoinRequestResult?
    func syncAndProcessJoinRequests(
        for conversationId: String,
        client: AnyClientProvider
    ) async throws -> JoinRequestResult?
    func processJoinRequests(
        since: Date?,
        client: AnyClientProvider
    ) async -> [JoinRequestResult]
    func hasOutgoingJoinRequest(
        for conversation: XMTPiOS.Conversation,
        client: AnyClientProvider
    ) async throws -> Bool
}

class InviteJoinRequestsManager: InviteJoinRequestsManagerProtocol {
    private let identityStore: any KeychainIdentityStoreProtocol
    private let databaseReader: any DatabaseReader

    init(identityStore: any KeychainIdentityStoreProtocol,
         databaseReader: any DatabaseReader) {
        self.identityStore = identityStore
        self.databaseReader = databaseReader
    }

    // MARK: - Public

    /// Process a message as a potential join request, with error handling
    /// - Parameters:
    ///   - message: The decoded message to process
    ///   - client: The XMTP client provider
    /// - Returns: The result if successful, nil otherwise
    private func processJoinRequestSafely(
        message: XMTPiOS.DecodedMessage,
        client: AnyClientProvider
    ) async -> JoinRequestResult? {
        do {
            if let result = try await processJoinRequest(
                message: message,
                client: client
            ) {
                Logger.info("Successfully added \(message.senderInboxId) to conversation \(result.conversationId)")
                return result
            }
            return nil
        } catch InviteJoinRequestError.missingTextContent {
            // Silently skip - not a join request
            return nil
        } catch InviteJoinRequestError.invalidInviteFormat {
            // Silently skip - not a join request
            return nil
        } catch InviteJoinRequestError.invalidSignature {
            Logger.error("Invalid signature in join request from \(message.senderInboxId)")
            return nil
        } catch InviteJoinRequestError.conversationNotFound(let id) {
            Logger.error("Conversation \(id) not found for join request from \(message.senderInboxId)")
            return nil
        } catch InviteJoinRequestError.invalidConversationType {
            Logger.error("Join request targets a DM instead of a group")
            return nil
        } catch {
            Logger.error("Error processing join request: \(error)")
            return nil
        }
    }

    /// Process a message as a potential join request
    /// - Parameters:
    ///   - message: The decoded message to process
    ///   - client: The XMTP client provider
    /// - Returns: The conversation details (ID and name) that the sender was added to, or nil if not a valid join request
    func processJoinRequest(
        message: XMTPiOS.DecodedMessage,
        client: AnyClientProvider
    ) async throws -> JoinRequestResult? {
        let senderInboxId = message.senderInboxId

        guard senderInboxId != client.inboxId else {
            Logger.info("Ignoring outgoing join request...")
            return nil
        }

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

        guard !signedInvite.hasExpired else {
            Logger.info("Invite expired, cancelling join request...")
            throw InviteJoinRequestError.expired
        }

        guard !signedInvite.conversationHasExpired else {
            Logger.info("Conversation expired, cancelling join request...")
            throw InviteJoinRequestError.expiredConversation
        }

        let creatorInboxId = signedInvite.payload.creatorInboxID
        guard creatorInboxId == client.inboxId else {
            Logger.error("Received join request for invite not created by this inbox")
            throw InviteJoinRequestError.invalidSignature
        }
        let identity = try await identityStore.identity(for: creatorInboxId)

        let publicKey = identity.keys.privateKey.publicKey.secp256K1Uncompressed.bytes

        do {
            let verifiedSignature = try signedInvite.verify(with: publicKey)
            guard verifiedSignature else {
                Logger.error("Failed verifying signature for invite from \(senderInboxId) - blocking DM")
                await blockDMConversation(client: client, conversationId: message.conversationId, senderInboxId: senderInboxId)
                throw InviteJoinRequestError.invalidSignature
            }
        } catch {
            Logger.error("Failed verifying signature for invite from \(senderInboxId) - blocking DM")
            await blockDMConversation(client: client, conversationId: message.conversationId, senderInboxId: senderInboxId)
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
            Logger.warning("Conversation \(conversationId) not found for join request from \(senderInboxId)")
            throw InviteJoinRequestError.conversationNotFound(conversationId)
        }

        switch conversation {
        case .group(let group):
            Logger.info("Adding \(senderInboxId) to group \(group.id)...")
            try await group.add(members: [senderInboxId])
            let conversationName = try? group.name()
            return JoinRequestResult(
                conversationId: group.id,
                conversationName: conversationName
            )
        case .dm:
            Logger.warning("Expected Group but found DM from \(senderInboxId), ignoring invite join request")
            throw InviteJoinRequestError.invalidConversationType
        }
    }

    func syncAndProcessJoinRequests(
        for conversationId: String,
        client: AnyClientProvider
    ) async throws -> JoinRequestResult? {
        _ = try await client.conversationsProvider.syncAllConversations(consentStates: [.unknown])
        guard let conversation = try await client.conversationsProvider.findConversation(conversationId: conversationId) else {
            return nil
        }
        return try await processMessages(for: conversation, client: client)
    }

    func hasOutgoingJoinRequest(for conversation: XMTPiOS.Conversation, client: AnyClientProvider) async throws -> Bool {
        let inviteTag = try conversation.inviteTag

        // List all DMs
        let dms = try client.conversationsProvider.listDms(
            createdAfterNs: nil,
            createdBeforeNs: nil,
            lastActivityBeforeNs: nil,
            lastActivityAfterNs: nil,
            limit: nil,
            consentStates: [.allowed],
            orderBy: .lastActivity
        )

        Logger.info("Found \(dms.count) possible DMs containing outgoing join requests")

        for dm in dms {
            do {
                let messages = try await dm.messages(afterNs: nil)
                    .filter { message in
                        // Filter by outgoing text content messages
                        guard let encodedContentType = try? message.encodedContent.type else {
                            return false
                        }

                        switch encodedContentType {
                        case ContentTypeText:
                            return message.senderInboxId == client.inboxId
                        default:
                            return false
                        }
                    }
                Logger.info("Found \(messages.count) outgoing messages as possible join requests")

                let invites: [SignedInvite] = messages.compactMap { message in
                    guard let text: String = try? message.content() else {
                        return nil
                    }
                    return try? SignedInvite.fromURLSafeSlug(text)
                }

                // return true if we've sent an outgoing join request for this conversation
                if invites.contains(where: { $0.payload.tag == inviteTag }) {
                    return true
                }
            } catch {
                Logger.error("Error processing messages as join requests: \(error.localizedDescription)")
            }
        }

        return false
    }

    /// Sync all DMs and process join requests, returning results
    /// - Parameter client: The XMTP client provider
    /// - Returns: Array of successfully processed join requests
    func processJoinRequests(since: Date?, client: AnyClientProvider) async -> [JoinRequestResult] {
        var results: [JoinRequestResult] = []

        do {
            Logger.info("Listing all DMs for join requests...")

            // List all DMs with consent states .unknown
            let dms = try client.conversationsProvider.listDms(
                createdAfterNs: nil,
                createdBeforeNs: nil,
                lastActivityBeforeNs: nil,
                lastActivityAfterNs: since?.nanosecondsSince1970,
                limit: nil,
                consentStates: [.unknown],
                orderBy: .lastActivity
            )

            Logger.info("Found \(dms.count) DMs to check for join requests")

            // Process each DM in parallel
            await withTaskGroup(of: JoinRequestResult?.self) { group in
                for dm in dms {
                    group.addTask { [weak self] in
                        do {
                            guard let self else { return nil }
                            return try await processMessages(for: dm, client: client)
                        } catch {
                            Logger.error("Error processing messages as join requests: \(error.localizedDescription)")
                            return nil
                        }
                    }
                }

                for await result in group {
                    if let result = result {
                        results.append(result)
                    }
                }
            }

            Logger.info("Completed DM sync for join requests")
        } catch {
            Logger.error("Error syncing DMs: \(error)")
        }

        return results
    }

    // MARK: - Private Helpers

    private func processMessages(for conversation: XMTPiOS.Conversation, client: AnyClientProvider) async throws -> JoinRequestResult? {
        guard case let .dm(dm) = conversation else { return nil }
        return try await processMessages(for: dm, client: client)
    }

    private func processMessages(for dm: XMTPiOS.Dm, client: AnyClientProvider) async throws -> JoinRequestResult? {
        let messages = try await dm.messages(afterNs: nil)
            .filter { message in
                guard let encodedContentType = try? message.encodedContent.type else {
                    return false
                }

                switch encodedContentType {
                case ContentTypeText:
                    return message.senderInboxId != client.inboxId
                default:
                    return false
                }
            }
        Logger.info("Found \(messages.count) messages as possible join requests")

        // Process each message and return first successful result for this DM
        for message in messages {
            if let result = await self.processJoinRequestSafely(
                message: message,
                client: client
            ) {
//                try await dm.updateConsentState(state: .allowed)
                return result
            }
        }
        return nil
    }

    /// Blocks a DM conversation by setting its consent state to denied
    private func blockDMConversation(
        client: AnyClientProvider,
        conversationId: String,
        senderInboxId: String
    ) async {
        guard let dmConversation = try? await client.conversationsProvider.findConversation(
            conversationId: conversationId
        ) else {
            return
        }

        do {
            try await dmConversation.updateConsentState(state: .denied)
            Logger.info("Set consent state to .denied for DM with \(senderInboxId)")
        } catch {
            Logger.error("Failed to set consent state to .denied for DM with \(senderInboxId): \(error)")
        }
    }
}
