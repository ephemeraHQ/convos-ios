import Foundation
import GRDB
import XMTPiOS

private extension AppEnvironment {
    var xmtpEnv: XMTPEnvironment {
        switch self {
        case .local, .tests: return .local
        case .dev: return .dev
        case .production: return .production
        }
    }

    var customLocalAddress: String? {
        guard let endpoint = self.xmtpEndpoint, !endpoint.isEmpty else {
            return nil
        }
        return endpoint
    }

    var isSecure: Bool {
        switch self {
        case .local, .tests:
            return false
        default:
            return true
        }
    }
}

extension InboxStateMachine.State {
    var isReady: Bool {
        switch self {
        case .ready:
            return true
        default:
            return false
        }
    }

    var clientId: String {
        switch self {
        case .idle(let clientId),
             .authorizing(let clientId, _),
             .registering(let clientId),
             .authenticatingBackend(let clientId, _),
             .ready(let clientId, _),
             .deleting(let clientId, _),
             .stopping(let clientId),
             .error(let clientId, _):
            return clientId
        }
    }
}

enum InboxStateError: Error {
    case inboxNotReady
}

public struct InboxReadyResult {
    public let client: any XMTPClientProvider
    public let apiClient: any ConvosAPIClientProtocol
}

typealias AnySyncingManager = (any SyncingManagerProtocol)
typealias AnyInviteJoinRequestsManager = (any InviteJoinRequestsManagerProtocol)

public actor InboxStateMachine {
    enum Action {
        case authorize(inboxId: String, clientId: String),
             register(clientId: String),
             clientAuthorized(clientId: String, client: any XMTPClientProvider),
             clientRegistered(clientId: String, client: any XMTPClientProvider),
             authorized(clientId: String, result: InboxReadyResult),
             delete,
             stop
    }

    public enum State {
        case idle(clientId: String)
        case authorizing(clientId: String, inboxId: String)
        case registering(clientId: String)
        case authenticatingBackend(clientId: String, inboxId: String)
        case ready(clientId: String, result: InboxReadyResult)
        case deleting(clientId: String, inboxId: String?)
        case stopping(clientId: String)
        case error(clientId: String, error: Error)
    }

    // MARK: -

    private let identityStore: any KeychainIdentityStoreProtocol
    private let invitesRepository: any InvitesRepositoryProtocol
    private let environment: AppEnvironment
    private let syncingManager: AnySyncingManager?
    private let savesInboxToDatabase: Bool
    private let autoRegistersForPushNotifications: Bool
    private let databaseWriter: any DatabaseWriter
    private lazy var deviceRegistrationManager: DeviceRegistrationManager = {
        DeviceRegistrationManager(environment: environment)
    }()

    private var currentTask: Task<Void, Never>?
    private var actionQueue: [Action] = []
    private var isProcessing: Bool = false
    private var pushTokenObserver: NSObjectProtocol?

    deinit {
        removePushTokenObserver()
    }

    // MARK: - State Observation

    private var stateContinuations: [AsyncStream<State>.Continuation] = []
    let initialClientId: String
    private var _state: State

    var state: State {
        get async {
            _state
        }
    }

    var inboxId: String? {
        switch _state {
        case .authorizing(_, let inboxId),
                .authenticatingBackend(_, let inboxId):
            return inboxId
        case .deleting(_, let inboxId):
            return inboxId
        case .ready(_, let result):
            return result.client.inboxId
        default:
            return nil
        }
    }

    var stateSequence: AsyncStream<State> {
        AsyncStream { continuation in
            Task { [weak self] in
                guard let self else { return }
                await self.addStateContinuation(continuation)
            }
        }
    }

    private func addStateContinuation(_ continuation: AsyncStream<State>.Continuation) {
        stateContinuations.append(continuation)
        continuation.onTermination = { [weak self] _ in
            Task {
                await self?.removeStateContinuation(continuation)
            }
        }
        continuation.yield(_state)
    }

    private func emitStateChange(_ newState: State) {
        _state = newState

        // Emit to all continuations
        for continuation in stateContinuations {
            continuation.yield(newState)
        }
    }

    private func removeStateContinuation(_ continuation: AsyncStream<State>.Continuation) {
        stateContinuations.removeAll { $0 == continuation }
    }

    private func cleanupContinuations() {
        stateContinuations.removeAll { continuation in
            continuation.finish()
            return true
        }
    }

    // MARK: - Init

    init(
        clientId: String,
        identityStore: any KeychainIdentityStoreProtocol,
        invitesRepository: any InvitesRepositoryProtocol,
        databaseWriter: any DatabaseWriter,
        syncingManager: AnySyncingManager?,
        savesInboxToDatabase: Bool = true,
        autoRegistersForPushNotifications: Bool = true,
        environment: AppEnvironment
    ) {
        self.initialClientId = clientId
        self._state = .idle(clientId: clientId)
        self.identityStore = identityStore
        self.invitesRepository = invitesRepository
        self.databaseWriter = databaseWriter
        self.syncingManager = syncingManager
        self.savesInboxToDatabase = savesInboxToDatabase
        self.autoRegistersForPushNotifications = autoRegistersForPushNotifications
        self.environment = environment

        // Set custom XMTP host if provided
        Logger.info("🔧 XMTP Configuration:")
        Logger.info("   XMTP_CUSTOM_HOST = \(environment.xmtpEndpoint ?? "nil")")
        Logger.info("   customLocalAddress = \(environment.customLocalAddress ?? "nil")")
        Logger.info("   xmtpEnv = \(environment.xmtpEnv)")
        Logger.info("   isSecure = \(environment.isSecure)")

        // Log the actual XMTPEnvironment.customLocalAddress after setting
        if let customHost = environment.customLocalAddress {
            Logger.info("🌐 Setting XMTPEnvironment.customLocalAddress = \(customHost)")
            XMTPEnvironment.customLocalAddress = customHost
            Logger.info("🌐 Actual XMTPEnvironment.customLocalAddress = \(XMTPEnvironment.customLocalAddress ?? "nil")")
        } else {
            Logger.info("🌐 Using default XMTP endpoints")
        }
    }

    // MARK: - Public

    func authorize(inboxId: String, clientId: String) {
        enqueueAction(.authorize(inboxId: inboxId, clientId: clientId))
    }

    func register(clientId: String) {
        enqueueAction(.register(clientId: clientId))
    }

    func stop() {
        enqueueAction(.stop)
    }

    func stopAndDelete() {
        enqueueAction(.delete)
    }

    /// Registers for push notifications once the inbox is in a ready state.
    func registerForPushNotifications() async {
        Logger.info("Manually triggering push notification registration")
        setupPushTokenObserver()

        // Check if we're already in ready state
        if case .ready = _state {
            await deviceRegistrationManager.registerDeviceIfNeeded()
            return
        }

        Logger.info("Inbox not ready, waiting to register for push notifications...")
        // Wait for ready state
        for await state in stateSequence {
            switch state {
            case .ready:
                await deviceRegistrationManager.registerDeviceIfNeeded()
                return
            case .error, .stopping, .deleting:
                // Don't wait if we're in an error or terminal state
                Logger.warning("Cannot register for push notifications in state: \(state)")
                return
            default:
                // Continue waiting for ready state
                continue
            }
        }
    }

    // MARK: - Private

    private func enqueueAction(_ action: Action) {
        actionQueue.append(action)
        processNextAction()
    }

    private func processNextAction() {
        guard !isProcessing, !actionQueue.isEmpty else { return }

        isProcessing = true
        let action = actionQueue.removeFirst()

        currentTask = Task.detached { [weak self] in
            guard let self else { return }
            await self.processAction(action)
            await self.setProcessingComplete()
        }
    }

    private func setProcessingComplete() {
        isProcessing = false
        processNextAction()
    }

    private func processAction(_ action: Action) async {
        do {
            switch (_state, action) {
            case let (.idle, .authorize(inboxId, clientId)):
                try await handleAuthorize(inboxId: inboxId, clientId: clientId)
            case let (.error(erroredClientId, _), .authorize(inboxId, clientId)):
                try await handleStop(clientId: erroredClientId)
                try await handleAuthorize(inboxId: inboxId, clientId: clientId)

            case (.idle, let .register(clientId)):
                try await handleRegister(clientId: clientId)
            case let (.error(erroredClientId, _), .register(clientId)):
                try await handleStop(clientId: erroredClientId)
                try await handleRegister(clientId: clientId)

            case (.authorizing, let .clientAuthorized(clientId, client)):
                try await handleClientAuthorized(clientId: clientId, client: client)
            case (.registering, let .clientRegistered(clientId, client)):
                try await handleClientRegistered(clientId: clientId, client: client)

            case (.authenticatingBackend, let .authorized(clientId, result)):
                try await handleAuthorized(
                    clientId: clientId,
                    client: result.client,
                    apiClient: result.apiClient
                )

            case (let .ready(clientId, result), .delete):
                try await handleDelete(clientId: clientId, client: result.client, apiClient: result.apiClient)
            case (let .error(clientId, _), .delete):
                try await handleDeleteFromError(clientId: clientId)
            case let (.ready(clientId, _), .stop),
                let (.error(clientId, _), .stop),
                let (.deleting(clientId, _), .stop):
                try await handleStop(clientId: clientId)

            case (.idle, .stop), (.stopping, .stop):
                break

            default:
                Logger.warning("Invalid state transition: \(_state) -> \(action)")
            }
        } catch {
            Logger.error(
                "Failed state transition \(_state) -> \(action): \(error.localizedDescription)"
            )
            // We always have a clientId now
            emitStateChange(.error(clientId: _state.clientId, error: error))
        }
    }

    private func handleAuthorize(inboxId: String, clientId: String) async throws {
        let identity = try await identityStore.identity(for: inboxId)

        // Verify clientId matches
        guard identity.clientId == clientId else {
            throw KeychainIdentityStoreError.identityNotFound("ClientId mismatch: expected \(clientId), got \(identity.clientId)")
        }

        emitStateChange(.authorizing(clientId: clientId, inboxId: inboxId))
        Logger.info("Started authorization flow for inbox: \(inboxId), clientId: \(clientId)")

        let keys = identity.clientKeys
        let clientOptions = clientOptions(keys: keys)
        let client: any XMTPClientProvider
        do {
            client = try await buildXmtpClient(
                inboxId: identity.inboxId,
                identity: keys.signingKey.identity,
                options: clientOptions
            )
        } catch {
            Logger.info("Error building client, trying create...")
            client = try await createXmtpClient(
                signingKey: keys.signingKey,
                options: clientOptions
            )
            // Update state to match the newly created client's inboxId
            emitStateChange(.authorizing(clientId: clientId, inboxId: client.inboxId))
            Logger.info("Updated state with new client inboxId: \(client.inboxId)")
        }

        if savesInboxToDatabase {
            // Ensure inbox is saved to database when authorizing
            // (in case it was registered as unused but is now being used)
            let inboxWriter = InboxWriter(dbWriter: databaseWriter)
            try await inboxWriter.save(inboxId: client.inboxId, clientId: identity.clientId)
            Logger.info("Ensured inbox is saved to database: \(client.inboxId)")
        } else {
            Logger.warning("Skipping save to database during authorization")
        }

        enqueueAction(.clientAuthorized(clientId: clientId, client: client))
    }

    private func handleRegister(clientId: String) async throws {
        emitStateChange(.registering(clientId: clientId))
        Logger.info("Started registration flow with clientId: \(clientId)")

        let keys = try await identityStore.generateKeys()
        let client = try await createXmtpClient(
            signingKey: keys.signingKey,
            options: clientOptions(keys: keys)
        )

        Logger.info("Generated clientId: \(clientId) for inboxId: \(client.inboxId)")

        // Save to keychain with clientId
        _ = try await identityStore.save(inboxId: client.inboxId, clientId: clientId, keys: keys)

        // Conditionally save to database based on configuration
        if savesInboxToDatabase {
            do {
                let inboxWriter = InboxWriter(dbWriter: databaseWriter)
                try await inboxWriter.save(inboxId: client.inboxId, clientId: clientId)
                Logger.info("Saved inbox to database with clientId: \(clientId)")
            } catch {
                // Rollback keychain entry on database failure to maintain consistency
                Logger.error("Failed to save inbox to database, rolling back keychain: \(error)")
                try? await identityStore.delete(inboxId: client.inboxId)
                throw error
            }
        } else {
            Logger.info("Skipping database save for inbox: \(client.inboxId) (unused inbox)")
        }

        enqueueAction(.clientRegistered(clientId: clientId, client: client))
    }

    private func handleClientAuthorized(clientId: String, client: any XMTPClientProvider) async throws {
        emitStateChange(.authenticatingBackend(clientId: clientId, inboxId: client.inboxId))

        Logger.info("Authenticating API client...")
        let apiClient = try await authorizeConvosBackend(client: client)

        enqueueAction(.authorized(clientId: clientId, result: .init(client: client, apiClient: apiClient)))
    }

    private func handleClientRegistered(clientId: String, client: any XMTPClientProvider) async throws {
        emitStateChange(.authenticatingBackend(clientId: clientId, inboxId: client.inboxId))
        Logger.info("Authenticating backend for registration...")
        let apiClient = try await authorizeConvosBackend(client: client)
        enqueueAction(.authorized(clientId: clientId, result: .init(client: client, apiClient: apiClient)))
    }

    private func handleAuthorized(clientId: String, client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) async throws {
        emitStateChange(.ready(clientId: clientId, result: .init(client: client, apiClient: apiClient)))

        Logger.info("Authorized, state machine is ready.")

        await syncingManager?.start(with: client, apiClient: apiClient)

        if autoRegistersForPushNotifications {
            // Register device on app launch (without push token - that's OK)
            // This creates the device record in the backend
            await deviceRegistrationManager.registerDeviceIfNeeded()

            // Setup push token observer to re-register when token arrives
            // Push permissions are requested when user creates/joins their first conversation
            setupPushTokenObserver()
            Logger.info("Device registered and push token observer set up. Will request permissions when user creates/joins a conversation.")
        } else {
            Logger.info("Auto push notification registration is disabled, skipping push notification setup")
        }
    }

    private func handleDelete(clientId: String, client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) async throws {
        Logger.info("Deleting inbox with clientId: \(clientId)...")
        let inboxId = client.inboxId
        emitStateChange(.deleting(clientId: clientId, inboxId: inboxId))

        // Perform common cleanup operations
        try await performInboxCleanup(clientId: clientId, client: client, apiClient: apiClient)

        enqueueAction(.stop)
    }

    private func handleDeleteFromError(clientId: String) async throws {
        Logger.info("Deleting inbox from error state...")
        defer { enqueueAction(.stop) }

        let currentInboxId = inboxId

        emitStateChange(.deleting(clientId: clientId, inboxId: currentInboxId))

        await syncingManager?.stop()

        // Clean up database records and keychain if we have an inbox ID
        try await cleanupInboxData(clientId: clientId)
        try await identityStore.delete(clientId: clientId)
        Logger.info("Deleted inbox with clientId \(clientId)")
    }

    private func handleStop(clientId: String) async throws {
        Logger.info("Stopping inbox...")
        emitStateChange(.stopping(clientId: clientId))
        await syncingManager?.stop()
        removePushTokenObserver()
        emitStateChange(.idle(clientId: clientId))
    }

    /// Performs common cleanup operations when deleting an inbox
    private func performInboxCleanup(clientId: String, client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) async throws {
        // Stop all services
        await syncingManager?.stop()

        // Unsubscribe from inbox-level welcome topic and unregister installation from backend
        // Note: Conversation topics are handled by ConversationStateMachine.cleanUp()
        let welcomeTopic = client.installationId.xmtpWelcomeTopicFormat

        // Unsubscribe from welcome topic (inbox-level topic only)
        do {
            try await apiClient.unsubscribeFromTopics(clientId: clientId, topics: [welcomeTopic])
            Logger.info("Unsubscribed from welcome topic: \(welcomeTopic)")
        } catch {
            Logger.error("Failed to unsubscribe from welcome topic: \(error)")
            // Continue with cleanup even if unsubscribe fails
        }

        // Unregister installation
        do {
            try await apiClient.unregisterInstallation(clientId: clientId)
            Logger.info("Unregistered installation from backend: \(clientId)")
        } catch {
            // Ignore errors during unregistration (common during account deletion when auth may be invalid)
            Logger.info("Could not unregister installation (likely during account deletion): \(error)")
        }

        // Revoke installation if identity is available
        if let identity = try? await identityStore.identity(for: client.inboxId) {
            let keys = identity.clientKeys
            do {
                try await client.revokeInstallations(
                    signingKey: keys.signingKey,
                    installationIds: [client.installationId]
                )
            } catch {
                Logger.error("Failed revoking installation: \(error.localizedDescription)")
            }
        } else {
            Logger.warning("Identity not found, skipping revoking installation...")
        }

        // Clean up all database records for this inbox
        try await cleanupInboxData(clientId: clientId)

        // Delete identity and local database
        try await identityStore.delete(clientId: clientId)
        try client.deleteLocalDatabase()

        // Delete database files
        deleteDatabaseFiles(for: client.inboxId)

        Logger.info("Deleted inbox \(client.inboxId) with clientId \(clientId)")
    }

    private func deleteDatabaseFiles(for inboxId: String) {
        let fileManager = FileManager.default
        let dbDirectory = environment.defaultDatabasesDirectoryURL

        // XMTP creates files like: xmtp-{env}-{inboxId}.db3
        // Note: .local environment uses "localhost" in filename, not "local"
        let envPrefix: String
        switch environment.xmtpEnv {
        case .local:
            envPrefix = "localhost"
        case .dev:
            envPrefix = "dev"
        case .production:
            envPrefix = "production"
        @unknown default:
            envPrefix = "unknown"
        }

        let dbBaseName = "xmtp-\(envPrefix)-\(inboxId)"

        let filesToDelete = [
            "\(dbBaseName).db3",
            "\(dbBaseName).db3.sqlcipher_salt",
            "\(dbBaseName).db3-shm",
            "\(dbBaseName).db3-wal"
        ]

        for filename in filesToDelete {
            let fileURL = dbDirectory.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: fileURL.path) {
                do {
                    try fileManager.removeItem(at: fileURL)
                    Logger.info("Deleted XMTP database file: \(filename)")
                } catch {
                    Logger.error("Failed to delete XMTP database file \(filename): \(error)")
                }
            }
        }
    }

    /// Deletes all database records associated with a given inboxId
    private func cleanupInboxData(clientId: String) async throws {
        Logger.info("Cleaning up all data for inbox clientId: \(clientId)")

        try await databaseWriter.write { db in
            // First, fetch all conversation IDs for this inbox
            let conversationIds = try DBConversation
                .filter(DBConversation.Columns.clientId == clientId)
                .fetchAll(db)
                .map { $0.id }

            Logger.info("Found \(conversationIds.count) conversations to clean up for inbox clientId: \(clientId)")

            // Delete messages for all conversations belonging to this inbox
            for conversationId in conversationIds {
                try DBMessage
                    .filter(DBMessage.Columns.conversationId == conversationId)
                    .deleteAll(db)
            }

            // Delete conversation members for all conversations
            for conversationId in conversationIds {
                try DBConversationMember
                    .filter(DBConversationMember.Columns.conversationId == conversationId)
                    .deleteAll(db)
            }

            // Delete conversation local states
            for conversationId in conversationIds {
                try ConversationLocalState
                    .filter(ConversationLocalState.Columns.conversationId == conversationId)
                    .deleteAll(db)
            }

            // Delete invites for all conversations
            for conversationId in conversationIds {
                try DBInvite
                    .filter(DBInvite.Columns.conversationId == conversationId)
                    .deleteAll(db)
            }

            // Delete member profiles for this inbox
            for conversationId in conversationIds {
                try MemberProfile
                    .filter(MemberProfile.Columns.conversationId == conversationId)
                    .deleteAll(db)
            }

            // Delete the member record for this inbox
            if let inboxId: String = try? DBInbox
                .filter(DBInbox.Columns.clientId == clientId)
                .fetchOne(db)?
                .inboxId {
                try Member
                    .filter(Member.Columns.inboxId == inboxId)
                    .deleteAll(db)
            }

            // Delete all conversations for this inbox
            try DBConversation
                .filter(DBConversation.Columns.clientId == clientId)
                .deleteAll(db)

            // Finally, delete the inbox record itself
            try DBInbox
                .filter(DBInbox.Columns.clientId == clientId)
                .deleteAll(db)

            Logger.info("Successfully cleaned up all data for inbox clientId: \(clientId)")
        }
    }

    // MARK: - Helpers

    private func clientOptions(keys: any XMTPClientKeys) -> ClientOptions {
        ClientOptions(
            api: .init(
                env: environment.xmtpEnv,
                isSecure: environment.isSecure,
                appVersion: "convos/\(Bundle.appVersion)"
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
    }

    private func createXmtpClient(signingKey: SigningKey,
                                  options: ClientOptions) async throws -> any XMTPClientProvider {
        Logger.info("Creating XMTP client...")
        let client = try await Client.create(account: signingKey, options: options)
        Logger.info("XMTP Client created with app version: convos/\(Bundle.appVersion)")
        return client
    }

    private func buildXmtpClient(inboxId: String,
                                 identity: PublicIdentity,
                                 options: ClientOptions) async throws -> any XMTPClientProvider {
        Logger.info("Building XMTP client for \(inboxId)...")
        let client = try await Client.build(
            publicIdentity: identity,
            options: options,
            inboxId: inboxId
        )
        Logger.info("XMTP Client built.")
        return client
    }

    private func initializeApiClient(client: any XMTPClientProvider) -> any ConvosAPIClientProtocol {
        Logger.info("Initializing API client...")
        return ConvosAPIClientFactory.authenticatedClient(
            client: client,
            environment: environment
        )
    }

    private func authorizeConvosBackend(client: any XMTPClientProvider) async throws -> any ConvosAPIClientProtocol {
        Logger.info("Authorizing backend with lazy authentication...")
        let apiClient = initializeApiClient(client: client)

        // Make a test call to trigger (re)authentication if needed
        Logger.info("Testing authentication with /auth-check...")
        _ = try await apiClient.checkAuth()

        return apiClient
    }

    // MARK: - Push Token Observer

    private func setupPushTokenObserver() {
        guard pushTokenObserver == nil else { return }

        Logger.info("Setting up push token observer...")
        pushTokenObserver = NotificationCenter.default.addObserver(
            forName: .convosPushTokenDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.handlePushTokenChange()
            }
        }
    }

    private func removePushTokenObserver() {
        if let observer = pushTokenObserver {
            NotificationCenter.default.removeObserver(observer)
            pushTokenObserver = nil
            Logger.info("Removed push token observer")
        }
    }

    private func handlePushTokenChange() async {
        guard case .ready = _state else {
            Logger.info("Push token changed but inbox not ready, skipping re-registration")
            return
        }

        Logger.info("Push token changed or became available, re-registering device...")
        await deviceRegistrationManager.registerDeviceIfNeeded()
    }
}
