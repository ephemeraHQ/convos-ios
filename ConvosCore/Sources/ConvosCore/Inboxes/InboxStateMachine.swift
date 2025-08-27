import Foundation
import Security
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
            (.initializing, .initializing),
            (.authorizing, .authorizing),
            (.registering, .registering),
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
        case authorize(inboxId: String),
             register,
             clientInitialized(any XMTPClientProvider),
             clientRegistered(any XMTPClientProvider),
             authorized(InboxReadyResult),
             delete,
             stop
    }

    public enum State {
        case uninitialized,
             initializing,
             authorizing,
             registering,
             ready(InboxReadyResult),
             deleting,
             stopping,
             error(Error)
    }

    // MARK: -

    private let identityStore: any KeychainIdentityStoreProtocol
    private let inboxWriter: any InboxWriterProtocol
    private let environment: AppEnvironment
    private let syncingManager: AnySyncingManager?
    private let inviteJoinRequestsManager: AnyInviteJoinRequestsManager?
    private let pushNotificationRegistrar: any PushNotificationRegistrarProtocol
    private let autoRegistersForPushNotifications: Bool
    private let shouldStartStreamingServicesOnReady: Bool
    private let deferBackendInitialization: Bool
    private var persistInboxOnReady: Bool
    private var hasActivatedDeferredIdentity: Bool = false

    private var inboxId: String?
    private var currentTask: Task<Void, Never>?
    private var actionQueue: [Action] = []
    private var isProcessing: Bool = false
    private var pushTokenObserver: NSObjectProtocol?
    private var backendInitialized: Bool = false
    private let jwtService: KeychainService<ConvosJWTKeychainItem> = .init()
    private var isPushRegistrationInFlight: Bool = false

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
            Task { @MainActor in
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
        inboxWriter: any InboxWriterProtocol,
        syncingManager: AnySyncingManager?,
        inviteJoinRequestsManager: AnyInviteJoinRequestsManager?,
        pushNotificationRegistrar: any PushNotificationRegistrarProtocol,
        autoRegistersForPushNotifications: Bool,
        environment: AppEnvironment,
        shouldStartStreamingServicesOnReady: Bool = true,
        deferBackendInitialization: Bool = false,
        persistInboxOnReady: Bool = true
    ) {
        self.identityStore = identityStore
        self.inboxWriter = inboxWriter
        self.syncingManager = syncingManager
        self.inviteJoinRequestsManager = inviteJoinRequestsManager
        self.environment = environment
        self.pushNotificationRegistrar = pushNotificationRegistrar
        self.autoRegistersForPushNotifications = autoRegistersForPushNotifications
        self.shouldStartStreamingServicesOnReady = shouldStartStreamingServicesOnReady
        self.deferBackendInitialization = deferBackendInitialization
        self.persistInboxOnReady = persistInboxOnReady

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
        enqueueAction(.authorize(inboxId: inboxId))
    }

    func register() {
        enqueueAction(.register)
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
        setupPushNotificationObservers()

        // Check if we're already in ready state
        if case .ready(let result) = _state {
            await performPushNotificationRegistration(client: result.client, apiClient: result.apiClient)
            return
        }

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
            case (.uninitialized, let .authorize(inboxId)),
                (.error, let .authorize(inboxId)):
                try await handleAuthorize(inboxId: inboxId)
            case (.uninitialized, .register),
                (.error, .register):
                try await handleRegister()
            case (.initializing, let .clientInitialized(client)):
                try await handleClientInitialized(client)
            case (.initializing, let .clientRegistered(client)):
                try await handleClientRegistered(client)
            case (.authorizing, let .authorized(result)),
                (.registering, let .authorized(result)):
                try await handleAuthorized(
                    client: result.client,
                    apiClient: result.apiClient
                )
            case (let .ready(result), .delete):
                try await handleDelete(client: result.client, apiClient: result.apiClient)
            case (.error, .delete):
                try await handleDeleteFromError()
            case (.ready, .stop), (.error, .stop), (.deleting, .stop):
                try handleStop()
            case (.uninitialized, .stop):
                break
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

    private func handleAuthorize(inboxId: String) async throws {
        emitStateChange(.initializing)
        // keep the inbox id in case we need it for cleaning up after an error
        self.inboxId = inboxId

        let identity = try await identityStore.identity(for: inboxId)
        let keys = identity.clientKeys
        let clientOptions = clientOptions(keys: keys)
        let client: any XMTPClientProvider
        do {
            client = try await buildXmtpClient(
                inboxId: inboxId,
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
        enqueueAction(.clientInitialized(client))
    }

    private func handleRegister() async throws {
        emitStateChange(.initializing)
        let keys = try await identityStore.generateKeys()
        let client = try await createXmtpClient(
            signingKey: keys.signingKey,
            options: clientOptions(keys: keys)
        )
        _ = try await identityStore.save(inboxId: client.inboxId, keys: keys)
        enqueueAction(.clientRegistered(client))
    }

    private func handleClientInitialized(_ client: any XMTPClientProvider) async throws {
        emitStateChange(.authorizing)

        Logger.info("Creating API client...")
        let apiClient = createConvosAPIClient(client: client)

        if deferBackendInitialization {
            // Skip backend init for deferred identities
            enqueueAction(.authorized(.init(client: client, apiClient: apiClient)))
            return
        }

        // If JWT already exists, we consider backend initialized
        if !backendInitialized {
            emitStateChange(.registering)
            Logger.info("Initializing with backend...")
            _ = try await initWithBackend(
                client: client,
                apiClient: apiClient
            )
            backendInitialized = true
        } else {
            Logger.info("Skipping initWithBackend: already initialized for inbox \(client.inboxId)")
        }

        enqueueAction(.authorized(.init(client: client, apiClient: apiClient)))
    }

    private func handleClientRegistered(_ client: any XMTPClientProvider) async throws {
        emitStateChange(.authorizing)
        Logger.info("Creating API client for registration...")
        let apiClient = createConvosAPIClient(client: client)

        if deferBackendInitialization {
            enqueueAction(.authorized(.init(client: client, apiClient: apiClient)))
            return
        }

        if !backendInitialized {
            emitStateChange(.registering)
            Logger.info("Creating identity in backend...")
            _ = try await initWithBackend(
                client: client,
                apiClient: apiClient
            )
            backendInitialized = true
        } else {
            Logger.info("Skipping initWithBackend: already initialized for inbox \(client.inboxId)")
        }
        enqueueAction(.authorized(.init(client: client, apiClient: apiClient)))
    }

    private func handleAuthorized(client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) async throws {
        emitStateChange(.ready(.init(client: client, apiClient: apiClient)))

        // Optionally persist and start streaming services
        if persistInboxOnReady {
            try await inboxWriter.storeInbox(inboxId: client.inboxId)
        }

        if shouldStartStreamingServicesOnReady {
            syncingManager?.start(with: client, apiClient: apiClient)
            inviteJoinRequestsManager?.start(with: client, apiClient: apiClient)
        }

        // Setup push notification observers if registrar is provided
        if autoRegistersForPushNotifications {
            setupPushNotificationObservers()
            // Register synchronously after ready to ensure ordering after init
            await performPushNotificationRegistration(client: client, apiClient: apiClient)
        } else {
            Logger.info("Auto push notification registration is disabled, skipping push notification setup")
        }
    }

    private func handleDelete(client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) async throws {
        Logger.info("Deleting inbox '\(client.inboxId)'...")

        removePushNotificationObservers()
        await pushNotificationRegistrar.unregisterInstallation(client: client, apiClient: apiClient)

        emitStateChange(.deleting)
        syncingManager?.stop()
        inviteJoinRequestsManager?.stop()
        try await inboxWriter.deleteInbox(inboxId: client.inboxId)
        try await identityStore.delete(inboxId: client.inboxId)
        try client.deleteLocalDatabase()
        Logger.info("Successfully deleted inbox \(client.inboxId)")
        enqueueAction(.stop)
    }

    private func handleDeleteFromError() async throws {
        Logger.info("Deleting inbox from error state...")
        emitStateChange(.deleting)
        syncingManager?.stop()
        inviteJoinRequestsManager?.stop()
        if let inboxId = inboxId {
            try await inboxWriter.deleteInbox(inboxId: inboxId)
            try await identityStore.delete(inboxId: inboxId)
            Logger.info("Successfully deleted inbox \(inboxId)")
        }
        enqueueAction(.stop)
    }

    private func handleStop() throws {
        Logger.info("Stopping inbox...")
        emitStateChange(.stopping)
        syncingManager?.stop()
        inviteJoinRequestsManager?.stop()
        removePushNotificationObservers()
        emitStateChange(.uninitialized)
    }

    // MARK: - Helpers

    private func clientOptions(keys: any XMTPClientKeys) -> ClientOptions {
        ClientOptions(
            api: .init(
                env: environment.xmtpEnv,
                isSecure: environment.isSecure
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
        Logger.info("XMTP Client created.")
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

    private func createConvosAPIClient(client: any XMTPClientProvider) -> any ConvosAPIClientProtocol {
        Logger.info("Creating Convos API client...")
        return ConvosAPIClientFactory.authenticatedClient(
            client: client,
            environment: environment
        )
    }

    // MARK: - Init

    private func initWithBackend(
        client: any XMTPClientProvider,
        apiClient: any ConvosAPIClientProtocol
    ) async throws -> ConvosAPI.InitResponse {
        let requestBody: ConvosAPI.InitRequest = .init(
            device: .current(),
            identity: .init(identityAddress: nil,
                            xmtpId: client.inboxId,
                            xmtpInstallationId: client.installationId),
            profile: .empty
        )
        return try await apiClient.initWithBackend(requestBody)
    }
}

// MARK: - Deferred Activation

extension InboxStateMachine {
    func activateDeferredInbox(registersForPushNotifications: Bool) async {
        guard case let .ready(result) = _state else { return }
        guard deferBackendInitialization, !hasActivatedDeferredIdentity else { return }

        do {
            emitStateChange(.registering)
            // Rely on API client to single-flight and skip if already initialized
            _ = try await initWithBackend(client: result.client, apiClient: result.apiClient)
            hasActivatedDeferredIdentity = true
            backendInitialized = true

            // Persist inbox if it wasn't persisted
            if !persistInboxOnReady {
                try await inboxWriter.storeInbox(inboxId: result.client.inboxId)
                persistInboxOnReady = true
            }

            // Start streaming services if they were deferred
            if !shouldStartStreamingServicesOnReady {
                syncingManager?.start(with: result.client, apiClient: result.apiClient)
                inviteJoinRequestsManager?.start(with: result.client, apiClient: result.apiClient)
            }

            if registersForPushNotifications {
                setupPushNotificationObservers()
                await performPushNotificationRegistration(client: result.client, apiClient: result.apiClient)
            }

            // Re-emit ready with same result
            emitStateChange(.ready(result))
        } catch {
            Logger.error("Deferred activation failed: \(error)")
            emitStateChange(.error(error))
        }
    }
}

// MARK: - Push Notification Observers

extension InboxStateMachine {
    private func performPushNotificationRegistration(client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) async {
        guard backendInitialized else {
            Logger.info("Skipping push registration: backend not initialized yet")
            return
        }
        guard !isPushRegistrationInFlight else { return }
        isPushRegistrationInFlight = true
        defer { isPushRegistrationInFlight = false }
        Logger.info("Registering for push notifications")
        // Attempt to register for remote notifications to obtain APNS token ASAP
        await pushNotificationRegistrar.registerForRemoteNotifications()

        // Request system notification authorization (APNS registration is handled separately)
        await pushNotificationRegistrar.requestNotificationAuthorizationIfNeeded()

        // Register backend notifications mapping (deviceId + token + identity + installation)
        await pushNotificationRegistrar.registerForNotificationsIfNeeded(client: client, apiClient: apiClient)
    }

    private func setupPushNotificationObservers() {
        guard pushTokenObserver == nil else { return }
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
        guard backendInitialized else {
            Logger.info("Ignoring token change: backend not initialized")
            return
        }
        guard case let .ready(result) = _state else { return }
        guard !isPushRegistrationInFlight else { return }
        isPushRegistrationInFlight = true
        defer { isPushRegistrationInFlight = false }
        await pushNotificationRegistrar.requestAuthAndRegisterIfNeeded(client: result.client, apiClient: result.apiClient)
    }
}
