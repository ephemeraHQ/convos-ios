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

    static func == (lhs: InboxStateMachine.State, rhs: InboxStateMachine.State) -> Bool {
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
    public let inbox: any AuthServiceInboxType
    public let client: any XMTPClientProvider
    public let apiClient: any ConvosAPIClientProtocol
}

public actor InboxStateMachine {
    enum Action {
        case authorize,
             register(String?),
             clientInitialized(any XMTPClientProvider),
             clientRegistered(any XMTPClientProvider, String?),
             authorized(InboxReadyResult),
             delete,
             stop
    }

    enum State {
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

    internal let inbox: any AuthServiceInboxType
    private let inboxWriter: any InboxWriterProtocol
    private let authService: any LocalAuthServiceProtocol
    private let environment: AppEnvironment
    private let clientOptions: ClientOptions
    private let syncingManager: any SyncingManagerProtocol
    private let inviteJoinRequestsManager: any InviteJoinRequestsManagerProtocol
    private let pushNotificationRegistrar: (any PushNotificationRegistrarProtocol)?

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
            Task { @MainActor in
                await self.addStateContinuation(continuation)
            }
        }
    }

    private func addStateContinuation(_ continuation: AsyncStream<State>.Continuation) {
        stateContinuations.append(continuation)
        continuation.yield(_state)
        continuation.onTermination = { [weak self] _ in
            Task {
                await self?.removeStateContinuation(continuation)
            }
        }
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
        inbox: any AuthServiceInboxType,
        inboxWriter: any InboxWriterProtocol,
        authService: any LocalAuthServiceProtocol,
        syncingManager: any SyncingManagerProtocol,
        inviteJoinRequestsManager: any InviteJoinRequestsManagerProtocol,
        pushNotificationRegistrar: (any PushNotificationRegistrarProtocol)? = nil,
        environment: AppEnvironment
    ) {
        self.inbox = inbox
        self.inboxWriter = inboxWriter
        self.authService = authService
        self.syncingManager = syncingManager
        self.inviteJoinRequestsManager = inviteJoinRequestsManager
        self.environment = environment
        self.pushNotificationRegistrar = pushNotificationRegistrar

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

        self.clientOptions = ClientOptions(
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
            dbEncryptionKey: inbox.databaseKey,
            dbDirectory: environment.defaultDatabasesDirectory
        )
    }

    // MARK: - Public

    func authorize() {
        enqueueAction(.authorize)
    }

    func register(displayName: String?) {
        enqueueAction(.register(displayName))
    }

    func stop() {
        enqueueAction(.stop)
    }

    func deleteAndStop() {
        enqueueAction(.delete)
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

        currentTask = Task {
            await processAction(action)
            isProcessing = false
            processNextAction()
        }
    }

    private func processAction(_ action: Action) async {
        do {
            switch (_state, action) {
            case (.uninitialized, .authorize),
                (.error, .authorize):
                try await handleAuthorize()
            case (.uninitialized, let .register(displayName)),
                (.error, let .register(displayName)):
                try await handleRegister(displayName: displayName)
            case (.initializing, let .clientInitialized(client)):
                try await handleClientInitialized(client)
            case (.initializing, let .clientRegistered(client, displayName)):
                try await handleClientRegistered(client, displayName: displayName)
            case (.authorizing, let .authorized(result)),
                (.registering, let .authorized(result)):
                try handleAuthorized(client: result.client, apiClient: result.apiClient)
            case (let .ready(result), .delete):
                try await handleDelete(client: result.client, apiClient: result.apiClient)
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

    private func handleAuthorize() async throws {
        emitStateChange(.initializing)
        let client: any XMTPClientProvider
        do {
            client = try await buildXmtpClient(
                identity: inbox.signingKey.identity,
                options: clientOptions
            )
        } catch {
            Logger.info("Error building client, trying create...")
            client = try await createXmtpClient(
                signingKey: inbox.signingKey,
                options: clientOptions
            )
        }
        enqueueAction(.clientInitialized(client))
    }

    private func handleRegister(displayName: String?) async throws {
        emitStateChange(.initializing)
        let client = try await createXmtpClient(
            signingKey: inbox.signingKey,
            options: clientOptions
        )
        try authService.save(inboxId: client.inboxId, for: inbox.providerId)
        enqueueAction(.clientRegistered(client, displayName))
    }

    private func handleClientInitialized(_ client: any XMTPClientProvider) async throws {
        emitStateChange(.authorizing)

        Logger.info("Authorizing backend for signin...")
        let apiClient = try await authorizeConvosBackend(client: client)

        enqueueAction(.authorized(.init(inbox: inbox, client: client, apiClient: apiClient)))
    }

    private func handleClientRegistered(_ client: any XMTPClientProvider, displayName: String?) async throws {
        emitStateChange(.authorizing)
        Logger.info("Authorizing backend for registration...")
        let apiClient = try await authorizeConvosBackend(client: client)
        emitStateChange(.registering)
        Logger.info("Creating identity in backend...")
        _ = try await createUser(
            client: client,
            apiClient: apiClient
        )
        try await inboxWriter.storeInbox(
            inboxId: client.inboxId,
            type: inbox.type,
            provider: inbox.provider,
            providerId: inbox.providerId
        )
        enqueueAction(.authorized(.init(inbox: inbox, client: client, apiClient: apiClient)))
    }

    private func handleAuthorized(client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) throws {
        emitStateChange(.ready(.init(inbox: inbox, client: client, apiClient: apiClient)))
        syncingManager.start(with: client, apiClient: apiClient)
        inviteJoinRequestsManager.start(with: client, apiClient: apiClient)

        // Setup push notification observers if registrar is provided
        if let pushNotificationRegistrar = pushNotificationRegistrar {
            setupPushNotificationObservers()

            Task {
                Logger.info("Registering for push notifications")
                // Attempt to register for remote notifications to obtain APNS token ASAP
                await pushNotificationRegistrar.registerForRemoteNotifications()

                // Request system notification authorization (APNS registration is handled separately)
                await pushNotificationRegistrar.requestNotificationAuthorizationIfNeeded()

                // Register backend notifications mapping (deviceId + token + identity + installation)
                await pushNotificationRegistrar.registerForNotificationsIfNeeded(client: client, apiClient: apiClient)
            }
        } else {
            Logger.info("Push notification registrar not available, skipping push notification setup")
        }
    }

    private func handleDelete(client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) async throws {
        Logger.info("Deleting inbox '\(client.inboxId)'...")

        await pushNotificationRegistrar?.unregisterInstallation(client: client, apiClient: apiClient)

        emitStateChange(.deleting)
        syncingManager.stop()
        inviteJoinRequestsManager.stop()
        try client.deleteLocalDatabase()
        try await inboxWriter.deleteInbox(inboxId: client.inboxId)
        Logger.info("Successfully deleted inbox \(client.inboxId)")
        enqueueAction(.stop)
    }

    private func handleStop() throws {
        Logger.info("Stopping inbox with providerId '\(inbox.providerId)'...")
        emitStateChange(.stopping)
        removePushNotificationObservers()
        emitStateChange(.uninitialized)
    }

    // MARK: - Helpers

    private func createXmtpClient(signingKey: SigningKey,
                                  options: ClientOptions) async throws -> any XMTPClientProvider {
        Logger.info("Creating XMTP client...")
        let client = try await Client.create(account: signingKey, options: options)
        Logger.info("XMTP Client created.")
        return client
    }

    private func buildXmtpClient(identity: PublicIdentity,
                                 options: ClientOptions) async throws -> any XMTPClientProvider {
        Logger.info("Building XMTP client...")
        let inboxId = try? authService.inboxId(for: inbox.providerId)
        if inboxId == nil {
            Logger.warning("Building XMTP client with nil inboxId")
        }
        let client = try await Client.build(
            publicIdentity: identity,
            options: options,
            inboxId: inboxId
        )
        Logger.info("XMTP Client built.")
        return client
    }

    private func authorizeConvosBackend(client: any XMTPClientProvider) async throws -> any ConvosAPIClientProtocol {
        Logger.info("Retrieving installation ID and Firebase App Check token...")
        let installationId = client.installationId
        let inboxId = client.inboxId
        let firebaseAppCheckToken = environment.appCheckToken
        let signatureData = try client.signWithInstallationKey(message: firebaseAppCheckToken)
        let signature = signatureData.hexEncodedString()
        Logger.info("Attempting to authenticate with Convos backend...")
        let apiClient = ConvosAPIClientFactory.authenticatedClient(
            client: client,
            environment: environment
        )
        _ = try await apiClient.authenticate(
            inboxId: inboxId,
            installationId: installationId,
            signature: signature
        )
        return apiClient
    }

    // MARK: - User Creation

    private func createUser(
        client: any XMTPClientProvider,
        apiClient: any ConvosAPIClientProtocol
    ) async throws -> ConvosAPI.CreatedUserResponse {
        let requestBody: ConvosAPI.CreateUserRequest = .init(
            userId: UUID().uuidString, // TODO: remove this
            userType: .onDevice,
            device: .current(),
            identity: .init(identityAddress: nil,
                            xmtpId: client.inboxId,
                            xmtpInstallationId: client.installationId),
            profile: .empty
        )
        return try await apiClient.createUser(requestBody)
    }
}

// MARK: - Push Notification Observers

extension InboxStateMachine {
    private func setupPushNotificationObservers() {
        guard pushNotificationRegistrar != nil else { return }

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
        guard let pushNotificationRegistrar = pushNotificationRegistrar else { return }
        guard case let .ready(result) = _state else { return }
        await pushNotificationRegistrar.requestAuthAndRegisterIfNeeded(client: result.client, apiClient: result.apiClient)
    }
}
