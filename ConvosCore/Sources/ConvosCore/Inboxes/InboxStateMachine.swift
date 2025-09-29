import Foundation
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
    private let autoRegistersForPushNotifications: Bool

    private var inboxId: String?
    private var currentTask: Task<Void, Never>?
    private var actionQueue: [Action] = []
    private var isProcessing: Bool = false
    private var pushTokenObserver: NSObjectProtocol?

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
        syncingManager: AnySyncingManager?,
        inviteJoinRequestsManager: AnyInviteJoinRequestsManager?,
        pushNotificationRegistrar: any PushNotificationRegistrarProtocol,
        autoRegistersForPushNotifications: Bool,
        environment: AppEnvironment
    ) {
        self.identityStore = identityStore
        self.invitesRepository = invitesRepository
        self.syncingManager = syncingManager
        self.inviteJoinRequestsManager = inviteJoinRequestsManager
        self.environment = environment
        self.pushNotificationRegistrar = pushNotificationRegistrar
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

    func authorize() {
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
        emitStateChange(.authorizing)

        Logger.info("Started authorization flow")

        do {
            let identity = try await identityStore.identity()
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
            enqueueAction(.clientAuthorized(client))
        } catch {
            Logger.warning("Failed authorizing, attempting registration...")
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
        _ = try await identityStore.save(inboxId: client.inboxId, keys: keys)
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
        Logger.info("Registering backend...")
//        _ = try await registerBackend(
//            client: client,
//            apiClient: apiClient
//        )
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
        if let inboxId = inboxId {
            try await identityStore.delete()
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
        if let identity = try? await identityStore.identity() {
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

        // Delete identity and local database
        try await identityStore.delete()
        try client.deleteLocalDatabase()
        Logger.info("Deleted inbox \(client.inboxId)")
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
//        _ = try await apiClient.checkAuth()

        return apiClient
    }

    // MARK: - Backend Init

    private func registerBackend(
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

// MARK: - Push Notification Observers

extension InboxStateMachine {
    private func performPushNotificationRegistration(client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) async {
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
        await pushNotificationRegistrar.requestAuthAndRegisterIfNeeded(client: result.client, apiClient: result.apiClient)
    }
}
