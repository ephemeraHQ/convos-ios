@testable import ConvosCore
import Foundation
import GRDB
import Testing
import XMTPiOS

/// Helper to wait for InboxStateMachine to reach a specific state with timeout
func waitForState(
    _ stateMachine: InboxStateMachine,
    timeout: TimeInterval = 30,
    condition: @escaping @Sendable (InboxStateMachine.State) -> Bool
) async throws -> InboxStateMachine.State {
    try await withTimeout(seconds: timeout) {
        for await state in await stateMachine.stateSequence {
            if condition(state) {
                return state
            }
        }
        throw TimeoutError()
    }
}

/// Test fixtures for creating XMTP clients in tests
class TestFixtures {
    let environment: AppEnvironment
    let identityStore: MockKeychainIdentityStore
    let keychainService: MockKeychainService
    let databaseManager: MockDatabaseManager

    var clientA: (any XMTPClientProvider)?
    var clientB: (any XMTPClientProvider)?
    var clientC: (any XMTPClientProvider)?

    var clientIdA: String?
    var clientIdB: String?
    var clientIdC: String?

    init() {
        self.environment = .tests
        self.identityStore = MockKeychainIdentityStore()
        self.keychainService = MockKeychainService()
        self.databaseManager = MockDatabaseManager.makeTestDatabase()
    }

    /// Create a new XMTP client for testing
    func createClient() async throws -> (client: any XMTPClientProvider, clientId: String, keys: KeychainIdentityKeys) {
        let keys = try await identityStore.generateKeys()
        let clientId = ClientId.generate().value

        let clientOptions = ClientOptions(
            api: .init(
                env: .local,
                isSecure: false,
                appVersion: "convos-tests/1.0.0"
            ),
            codecs: [
                TextCodec(),
                ReplyCodec(),
                ReactionCodec(),
                AttachmentCodec(),
                RemoteAttachmentCodec(),
                GroupUpdatedCodec(),
                ExplodeSettingsCodec()
            ],
            dbEncryptionKey: keys.databaseKey,
            dbDirectory: environment.defaultDatabasesDirectory
        )

        let client = try await Client.create(account: keys.signingKey, options: clientOptions)

        // Save to mock identity store
        _ = try await identityStore.save(inboxId: client.inboxId, clientId: clientId, keys: keys)

        return (client, clientId, keys)
    }

    /// Create three test clients (A, B, C) for testing
    func createTestClients() async throws {
        let (a, aId, _) = try await createClient()
        let (b, bId, _) = try await createClient()
        let (c, cId, _) = try await createClient()

        clientA = a
        clientB = b
        clientC = c
        clientIdA = aId
        clientIdB = bId
        clientIdC = cId
    }

    /// Clean up all test clients
    func cleanup() async throws {
        if let client = clientA {
            try? client.deleteLocalDatabase()
        }
        if let client = clientB {
            try? client.deleteLocalDatabase()
        }
        if let client = clientC {
            try? client.deleteLocalDatabase()
        }

        try await identityStore.deleteAll()
        try databaseManager.erase()
    }
}

/// Mock implementation of InvitesRepositoryProtocol for testing
class MockInvitesRepository: InvitesRepositoryProtocol {
    private var invites: [String: [Invite]] = [:]

    func fetchInvites(for creatorInboxId: String) async throws -> [Invite] {
        invites[creatorInboxId] ?? []
    }

    // Test helper methods
    func addInvite(_ invite: Invite, for creatorInboxId: String) {
        var existing = invites[creatorInboxId] ?? []
        existing.append(invite)
        invites[creatorInboxId] = existing
    }

    func clearInvites(for creatorInboxId: String) {
        invites.removeValue(forKey: creatorInboxId)
    }
}

/// Mock implementation of SyncingManagerProtocol for testing
actor MockSyncingManager: SyncingManagerProtocol {
    var isStarted = false
    var startCallCount = 0
    var stopCallCount = 0

    func start(with client: AnyClientProvider, apiClient: any ConvosAPIClientProtocol) {
        isStarted = true
        startCallCount += 1
    }

    func stop() {
        isStarted = false
        stopCallCount += 1
    }
}
