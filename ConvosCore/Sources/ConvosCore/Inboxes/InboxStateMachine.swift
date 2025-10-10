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

extension InboxStateMachine.State: Equatable {
    var isReady: Bool {
        switch self {
        case .ready:
            return true
        default:
            return false
        }
    }

    public static func == (lhs: InboxStateMachine.State, rhs: InboxStateMachine.State) -> Bool {
        switch (lhs, rhs) {
        case (.uninitialized, .uninitialized),
            (.authorizing, .authorizing),
            (.registering, .registering),
            (.authenticatingBackend, .authenticatingBackend),
            (.stopping, .stopping),
            (.deleting, .deleting),
            (.error, .error):
            return true
        case let (.ready(lhsResult),
                  .ready(rhsResult)):
            return (lhsResult.client.inboxId == rhsResult.client.inboxId &&
                    lhsResult.client.installationId == rhsResult.client.installationId &&
                    lhsResult.apiClient.identifier == rhsResult.apiClient.identifier)
        default:
            return false
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
        case authorize,
             clientAuthorized(any XMTPClientProvider),
             clientRegistered(any XMTPClientProvider),
             authorized(InboxReadyResult),
             delete,
             stop,
             reset
    }

    public enum State {
        case uninitialized,
             authorizing,
             registering,
             authenticatingBackend,
             ready(InboxReadyResult),
             deleting,
             stopping,
             error(Error)
    }

    // MARK: -

    private let identityStore: any KeychainIdentityStoreProtocol
    private let invitesRepository: any InvitesRepositoryProtocol
    private let environment: AppEnvironment
    private let syncingManager: AnySyncingManager?
    private let inviteJoinRequestsManager: AnyInviteJoinRequestsManager?
    private let pushNotificationRegistrar: any PushNotificationRegistrarProtocol
    private let savesInboxToDatabase: Bool
    private let autoRegistersForPushNotifications: Bool
    private let databaseWriter: any DatabaseWriter

    private var inboxId: String?
    private var currentTask: Task<Void, Never>?
    private var actionQueue: [Action] = []
    private var isProcessing: Bool = false
    private var pushTokenObserver: NSObjectProtocol?
    private var deviceRegistrationTask: Task<Void, Error>?
    private var isDeviceRegistered: Bool = false

    // MARK: - State Observation

    private var stateContinuations: [AsyncStream<State>.Continuation] = []
    private var _state: State = .uninitialized

    var state: State {
        get async {
            _state
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
        identityStore: any KeychainIdentityStoreProtocol,
        invitesRepository: any InvitesRepositoryProtocol,
        databaseWriter: any DatabaseWriter,
        syncingManager: AnySyncingManager?,
        inviteJoinRequestsManager: AnyInviteJoinRequestsManager?,
        pushNotificationRegistrar: any PushNotificationRegistrarProtocol,
        savesInboxToDatabase: Bool = true,
        autoRegistersForPushNotifications: Bool,
        environment: AppEnvironment
    ) {
        self.identityStore = identityStore
        self.invitesRepository = invitesRepository
        self.databaseWriter = databaseWriter
        self.syncingManager = syncingManager
        self.inviteJoinRequestsManager = inviteJoinRequestsManager
        self.environment = environment
        self.pushNotificationRegistrar = pushNotificationRegistrar
        self.savesInboxToDatabase = savesInboxToDatabase
        self.autoRegistersForPushNotifications = autoRegistersForPushNotifications

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

    func authorize(inboxId: String) {
        self.inboxId = inboxId
        enqueueAction(.authorize)
    }

    func register() {
        enqueueAction(.authorize)
    }

    func stop() {
        enqueueAction(.stop)
    }

    func stopAndDelete() {
        enqueueAction(.delete)
    }

    func reset() {
        enqueueAction(.reset)
    }

    /// Registers for push notifications once the inbox is in a ready state.
    func registerForPushNotifications() async {
        Logger.info("Manually triggering push notification registration")
        setupPushNotificationObservers()

        // Check if we're already in ready state
        if case .ready(let result) = _state {
            await performPushNotificationRegistration(client: result.client, apiClient: result.apiClient)
            return
        }

        Logger.info("Inbox not ready, waiting to register for push notifications...")
        // Wait for ready state
        for await state in stateSequence {
            switch state {
            case .ready(let result):
                await performPushNotificationRegistration(client: result.client, apiClient: result.apiClient)
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

    /// Ensures device is registered before subscribing to topics.
    /// This prevents race conditions where topic subscription happens before device registration.
    /// @lourou refactor
    func subscribeToTopicsWhenDeviceReady(topics: [String]) async throws {
        guard case .ready(let result) = _state else {
            throw InboxStateError.inboxNotReady
        }

        // Wait for device registration to complete
        try await waitForDeviceRegistration()

        // Now subscribe to topics
        let deviceId = DeviceInfo.deviceIdentifier
        try await result.apiClient.subscribeToTopics(
            deviceId: deviceId,
            clientId: result.client.installationId,
            topics: topics
        )
    }

    /// Waits for device registration to complete.
    private func waitForDeviceRegistration() async throws {
        // If already registered, return immediately
        if isDeviceRegistered {
            return
        }

        // If registration is in progress, wait for it
        if let task = deviceRegistrationTask {
            try await task.value
            return
        }

        // No registration in progress, but not registered yet
        // This can happen if push token hasn't arrived yet
        Logger.warning("Device registration not started yet, continuing anyway (push token may not be available)")
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
            case (.uninitialized, .authorize):
                try await handleAuthorize()
            case (.error, .authorize):
                try await handleStop()
                try await handleAuthorize()

            case (.authorizing, let .clientAuthorized(client)):
                try await handleClientAuthorized(client)
            case (.registering, let .clientRegistered(client)):
                try await handleClientRegistered(client)

            case (.authenticatingBackend, let .authorized(result)):
                try await handleAuthorized(
                    client: result.client,
                    apiClient: result.apiClient
                )

            case (let .ready(result), .delete):
                try await handleDelete(client: result.client, apiClient: result.apiClient)
            case (.error, .delete):
                try await handleDeleteFromError()
            case (.ready, .stop), (.error, .stop), (.deleting, .stop):
                try await handleStop()

            case (.uninitialized, .stop):
                break

            // Reset transitions
            case (let .ready(result), .reset):
                try await handleReset(client: result.client, apiClient: result.apiClient)
            case (.error, .reset), (.uninitialized, .reset):
                // If not ready, just start fresh authorization
                try await handleAuthorize()

            default:
                Logger.warning("Invalid state transition: \(_state) -> \(action)")
            }
        } catch {
            Logger.error(
                "Failed state transition \(_state) -> \(action): \(error.localizedDescription)"
            )
            emitStateChange(.error(error))
        }
    }

    private func handleAuthorize() async throws {
        // If no inboxId is set, this is a registration flow
        guard let inboxId = inboxId else {
            try await handleRegister()
            return
        }

        emitStateChange(.authorizing)
        Logger.info("Started authorization flow for inbox: \(inboxId)")

        do {
            let identity = try await identityStore.identity(for: inboxId)
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
            }

            if savesInboxToDatabase {
                // Ensure inbox is saved to database when authorizing
                // (in case it was registered as unused but is now being used)
                let inboxWriter = InboxWriter(dbWriter: databaseWriter)
                try await inboxWriter.save(inboxId: identity.inboxId, clientId: identity.clientId)
                Logger.info("Ensured inbox is saved to database: \(identity.inboxId)")
            } else {
                Logger.warning("Skipping save to database during authorization")
            }

            enqueueAction(.clientAuthorized(client))
        } catch {
            Logger.warning("Failed authorizing inbox \(inboxId), attempting registration...")
            try await handleRegister()
        }
    }

    private func handleRegister() async throws {
        emitStateChange(.registering)
        Logger.info("Started registration flow...")
        let keys = try await identityStore.generateKeys()
        let client = try await createXmtpClient(
            signingKey: keys.signingKey,
            options: clientOptions(keys: keys)
        )
        // Save the generated inboxId
        self.inboxId = client.inboxId

        // Generate a clientId for privacy
        let clientId = ClientId.generate()
        Logger.info("Generated clientId: \(clientId.value) for inboxId: \(client.inboxId)")

        // Save to keychain with clientId
        _ = try await identityStore.save(inboxId: client.inboxId, clientId: clientId.value, keys: keys)

        // Conditionally save to database based on configuration
        if savesInboxToDatabase {
            let inboxWriter = InboxWriter(dbWriter: databaseWriter)
            try await inboxWriter.save(inboxId: client.inboxId, clientId: clientId.value)
            Logger.info("Saved inbox to database with clientId: \(clientId.value)")
        } else {
            Logger.info("Skipping database save for inbox: \(client.inboxId) (unused inbox)")
        }

        enqueueAction(.clientRegistered(client))
    }

    private func handleClientAuthorized(_ client: any XMTPClientProvider) async throws {
        emitStateChange(.authenticatingBackend)

        Logger.info("Authenticating API client...")
        let apiClient = initializeApiClient(client: client)

        enqueueAction(.authorized(.init(client: client, apiClient: apiClient)))
    }

    private func handleClientRegistered(_ client: any XMTPClientProvider) async throws {
        emitStateChange(.authenticatingBackend)
        Logger.info("Authenticating backend for registration...")
        let apiClient = try await authorizeConvosBackend(client: client)
        enqueueAction(.authorized(.init(client: client, apiClient: apiClient)))
    }

    private func handleAuthorized(client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) async throws {
        emitStateChange(.ready(.init(client: client, apiClient: apiClient)))

        Logger.info("Authorized, state machine is ready.")

        await syncingManager?.start(with: client, apiClient: apiClient)
        inviteJoinRequestsManager?.start(with: client, apiClient: apiClient)

        // Setup push notification observers if registrar is provided
        if autoRegistersForPushNotifications {
            setupPushNotificationObservers()
            await performPushNotificationRegistration(client: client, apiClient: apiClient)
        } else {
            Logger.info("Auto push notification registration is disabled, skipping push notification setup")
        }
    }

    private func handleDelete(client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) async throws {
        Logger.info("Deleting inbox...")
        emitStateChange(.deleting)

        // Perform common cleanup operations
        try await performInboxCleanup(client: client, apiClient: apiClient)

        enqueueAction(.stop)
    }

    private func handleDeleteFromError() async throws {
        Logger.info("Deleting inbox from error state...")
        emitStateChange(.deleting)
        await syncingManager?.stop()
        inviteJoinRequestsManager?.stop()

        // Clean up database records and keychain if we have an inbox ID
        if let inboxId = inboxId {
            try await cleanupInboxData(inboxId: inboxId)
            try await identityStore.delete(inboxId: inboxId)
            Logger.info("Deleted inbox \(inboxId)")
        }

        enqueueAction(.stop)
    }

    private func handleStop() async throws {
        Logger.info("Stopping inbox...")
        emitStateChange(.stopping)
        await syncingManager?.stop()
        inviteJoinRequestsManager?.stop()
        removePushNotificationObservers()
        deviceRegistrationTask?.cancel()
        deviceRegistrationTask = nil
        isDeviceRegistered = false
        inboxId = nil
        emitStateChange(.uninitialized)
    }

    private func handleReset(client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) async throws {
        Logger.info("Resetting inbox...")
        emitStateChange(.deleting)

        // Perform common cleanup operations
        try await performInboxCleanup(client: client, apiClient: apiClient)

        // Transition to uninitialized
        inboxId = nil
        emitStateChange(.uninitialized)

        // Now start authorization
        try await handleAuthorize()
    }

    /// Performs common cleanup operations when deleting or resetting an inbox
    private func performInboxCleanup(client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) async throws {
        // Stop all services and observers
        removePushNotificationObservers()
        await pushNotificationRegistrar.unregisterInstallation(client: client, apiClient: apiClient)
        await syncingManager?.stop()
        inviteJoinRequestsManager?.stop()

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
        try await cleanupInboxData(inboxId: client.inboxId)

        // Delete identity and local database
        try await identityStore.delete(inboxId: client.inboxId)
        try client.deleteLocalDatabase()

        // Delete database files
        deleteDatabaseFiles(for: client.inboxId)

        Logger.info("Deleted inbox \(client.inboxId)")
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
    private func cleanupInboxData(inboxId: String) async throws {
        Logger.info("Cleaning up all data for inbox: \(inboxId)")

        try await databaseWriter.write { db in
            // First, fetch all conversation IDs for this inbox
            let conversationIds = try DBConversation
                .filter(DBConversation.Columns.inboxId == inboxId)
                .fetchAll(db)
                .map { $0.id }

            Logger.info("Found \(conversationIds.count) conversations to clean up for inbox: \(inboxId)")

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
            try Member
                .filter(Member.Columns.inboxId == inboxId)
                .deleteAll(db)

            // Delete all conversations for this inbox
            try DBConversation
                .filter(DBConversation.Columns.inboxId == inboxId)
                .deleteAll(db)

            // Finally, delete the inbox record itself
            try DBInbox
                .filter(DBInbox.Columns.inboxId == inboxId)
                .deleteAll(db)

            Logger.info("Successfully cleaned up all data for inbox: \(inboxId)")
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

}

// MARK: - Push Notification Observers

extension InboxStateMachine {
    private func performPushNotificationRegistration(client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) async {
        Logger.info("Registering for push notifications")

        // Track device registration as a task so topic subscriptions can wait for it
        deviceRegistrationTask = Task {
            do {
                // Step 1: Register device immediately without push token (early registration)
                // This allows the backend to know about the device before APNS token arrives
                try await pushNotificationRegistrar.registerDeviceWithoutToken(apiClient: apiClient)
                await markDeviceAsRegistered()

                // Step 2: Request APNS token from iOS system
                await pushNotificationRegistrar.registerForRemoteNotifications()

                // Step 3: Request system notification authorization
                await pushNotificationRegistrar.requestNotificationAuthorizationIfNeeded()

                // Step 4: If token is already available, update the registration
                // (Token may have been received from previous app sessions)
                await pushNotificationRegistrar.registerForNotificationsIfNeeded(client: client, apiClient: apiClient)
            } catch is CancellationError {
                Logger.info("Device registration was cancelled")
            } catch {
                Logger.error("Device registration failed: \(error)")
            }
        }

        // Wait for registration to complete
        try? await deviceRegistrationTask?.value
    }

    private func markDeviceAsRegistered() {
        isDeviceRegistered = true
        Logger.info("Device registration completed")
    }

    private func setupPushNotificationObservers() {
        guard pushTokenObserver == nil else { return }
        Logger.info("Started observing for push token change...")
        // Observe future token changes
        pushTokenObserver = NotificationCenter.default.addObserver(
            forName: .convosPushTokenDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.handleTokenChange()
            }
        }
    }

    private func removePushNotificationObservers() {
        if let pushTokenObserver { NotificationCenter.default.removeObserver(pushTokenObserver) }
        pushTokenObserver = nil
    }

    private func handleTokenChange() async {
        guard case let .ready(result) = _state else { return }

        // Reset registration state and register again with new token
        deviceRegistrationTask?.cancel()
        isDeviceRegistered = false

        deviceRegistrationTask = Task {
            await pushNotificationRegistrar.requestAuthAndRegisterIfNeeded(client: result.client, apiClient: result.apiClient)
            await markDeviceAsRegistered()
        }

        do {
            try await deviceRegistrationTask?.value
        } catch {
            Logger.error("Device re-registration after token change failed: \(error)")
        }
    }
}
