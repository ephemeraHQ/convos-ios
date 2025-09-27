import Foundation
import GRDB
import XMTPiOS

protocol InviteJoinRequestsManagerProtocol {
    func start(with client: AnyClientProvider,
               apiClient: any ConvosAPIClientProtocol)
    func stop()
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

    func start(with client: AnyClientProvider,
               apiClient: any ConvosAPIClientProtocol) {
        let inboxId = client.inboxId
        streamMessagesTask = Task { [weak self, client] in
            do {
                Logger.info("Started streaming messages...")
                for try await message in client.conversationsProvider
                    .streamAllMessages(
                        type: .dms,
                        consentStates: [.unknown],
                        onClose: {
                            Logger.warning("Closing streamAllMessages...")
                        }
                    ).filter({ $0.senderInboxId != inboxId }) {
                    guard let self else { return }
                    do {
                        let dbMessage = try message.dbRepresentation()
                        guard let text = dbMessage.text else {
                            continue
                        }

                        let signedInvite = try SignedInvite.fromURLSafeSlug(text)

                        // @jarodl do more validation here, if someone is sending bogus invites, block the inbox id

                        let identity = try await identityStore.identity()

                        let publicKey = identity.keys.privateKey.publicKey.secp256K1Uncompressed.bytes

                        let verifiedSignature = try signedInvite.verify(with: publicKey)

                        guard verifiedSignature else {
                            Logger.error("Failed verifying signature for invite, skipping message...")
                            continue
                        }

                        let privateKey: Data = identity.keys.privateKey.secp256K1.bytes
                        let code = signedInvite.payload.code
                        let conversationId = try InviteCode.decodeCode(
                            code,
                            creatorInboxId: client.inboxId,
                            secp256k1PrivateKey: privateKey
                        )

                        guard let conversation = try await client.conversationsProvider.findConversation(
                            conversationId: conversationId
                        ) else {
                            Logger.warning("Conversation not found on XMTP")
                            continue
                        }

                        switch conversation {
                        case .group(let group):
                            Logger.info("Adding \(message.senderInboxId) to group \(group.id)...")
                            try await group.add(members: [message.senderInboxId])
//                            Logger.info("Storing conversation with id: \(conversation.id)")
//                            try await conversationWriter.store(conversation: conversation)
                        case .dm:
                            Logger.warning("Expected Group but found DM, ignoring invite join request...")
                        }
                    } catch {
                        Logger.error("Error decoding message: \(error.localizedDescription)")
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
