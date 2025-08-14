import Combine
import Foundation
import UIKit
import UserNotifications
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

typealias InboxReadyResultPublisher = AnyPublisher<InboxReadyResult, Never>

struct InboxReadyResult {
    let inbox: any AuthServiceInboxType
    let client: any XMTPClientProvider
    let apiClient: any ConvosAPIClientProtocol
}

actor InboxStateMachine {
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

    let inbox: any AuthServiceInboxType
    private let inboxWriter: any InboxWriterProtocol
    private let environment: AppEnvironment
    private let clientOptions: ClientOptions
    private let syncingManager: any SyncingManagerProtocol
    private let inviteJoinRequestsManager: any InviteJoinRequestsManagerProtocol

    private var _state: State = .uninitialized {
        didSet {
            stateSubject.send(_state)
        }
    }

    private var currentTask: Task<Void, Never>?
    private var actionQueue: [Action] = []
    private var isProcessing: Bool = false
    private var pushTokenObserver: NSObjectProtocol?
    private var conversationUnsubscribeObserver: NSObjectProtocol?
    private var unregisterInstallationObserver: NSObjectProtocol?
    private var willEnterForegroundObserver: NSObjectProtocol?

    // MARK: - Nonisolated

    nonisolated
    var state: State {
        stateSubject.value
    }

    nonisolated
    private let stateSubject: CurrentValueSubject<State, Never> = .init(
        .uninitialized
    )

    nonisolated
    var statePublisher: AnyPublisher<State, Never> {
        stateSubject
            .eraseToAnyPublisher()
    }

    // MARK: - Init

    init(
        inbox: any AuthServiceInboxType,
        inboxWriter: any InboxWriterProtocol,
        syncingManager: any SyncingManagerProtocol,
        inviteJoinRequestsManager: any InviteJoinRequestsManagerProtocol,
        environment: AppEnvironment
    ) {
        self.inbox = inbox
        self.inboxWriter = inboxWriter
        self.syncingManager = syncingManager
        self.inviteJoinRequestsManager = inviteJoinRequestsManager
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
                GroupUpdatedCodec()
            ],
            dbEncryptionKey: inbox.databaseKey,
            dbDirectory: environment.defaultDatabasesDirectory
        )

        // Observe app foreground events to retry push token update when ready
        Task { [weak self] in
            await self?.registerForegroundObserver()
        }
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
                try await handleDelete(inboxId: result.client.inboxId)
            case (.ready, .stop), (.error, .stop):
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
            _state = .error(error)
        }
    }

    private func handleAuthorize() async throws {
        _state = .initializing
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
        _state = .initializing
        let client = try await createXmtpClient(
            signingKey: inbox.signingKey,
            options: clientOptions
        )
        enqueueAction(.clientRegistered(client, displayName))
    }

    private func handleClientInitialized(_ client: any XMTPClientProvider) async throws {
        _state = .authorizing
        Logger.info("Authorizing backend for signin...")
        let apiClient = try await authorizeConvosBackend(client: client)

        // Attempt to register for remote notifications to obtain APNS token ASAP
        await registerForRemoteNotificationsAlways()

        // Request system notification authorization (APNS registration is handled separately)
        await requestNotificationAuthorizationIfNeeded()

        // Register backend notifications mapping (deviceId + token + identity + installation)
        await registerForNotificationsIfNeeded(client: client, apiClient: apiClient)

        do {
            try await refreshUserAndProfile(client: client, apiClient: apiClient)
        } catch {
            Logger.error("Error refreshing user and profile: \(error.localizedDescription)")
        }
        enqueueAction(.authorized(.init(inbox: inbox, client: client, apiClient: apiClient)))
    }

    private func handleClientRegistered(_ client: any XMTPClientProvider, displayName: String?) async throws {
        _state = .authorizing
        Logger.info("Authorizing backend for registration...")
        let apiClient = try await authorizeConvosBackend(client: client)
        _state = .registering
        Logger.info("Creating user with display name '\(displayName ?? "nil")'...")
        let user = try await createUser(
            displayName: displayName,
            client: client,
            apiClient: apiClient
        )
        try await inboxWriter.storeInbox(
            inboxId: client.inboxId,
            user: user,
            type: inbox.type,
            provider: inbox.provider,
            providerId: inbox.providerId
        )
        enqueueAction(.authorized(.init(inbox: inbox, client: client, apiClient: apiClient)))
    }

    private func handleAuthorized(client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) throws {
        _state = .ready(.init(inbox: inbox, client: client, apiClient: apiClient))
        syncingManager.start(with: client, apiClient: apiClient)
        inviteJoinRequestsManager.start(with: client, apiClient: apiClient)
        Task { [weak self] in
            guard let self else { return }
            await self.updateIfReady()
        }
        // Observe future token changes
        pushTokenObserver = NotificationCenter.default.addObserver(
            forName: .convosPushTokenDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                await self.updateIfReady()
            }
        }

        // Observe conversation unsubscribe requests and propagate to backend
        conversationUnsubscribeObserver = NotificationCenter.default.addObserver(
            forName: .convosConversationUnsubscribeRequested,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let conversationId = note.userInfo?["conversationId"] as? String else { return }
            Task { [weak self] in
                guard let self else { return }
                await self.unsubscribeIfReady(conversationId: conversationId)
            }
        }

        // Unregister the installation (all topics) when requested (single-inbox delete uses handleDelete)
        unregisterInstallationObserver = NotificationCenter.default.addObserver(
            forName: .convosUnregisterAllInboxesRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                guard let self else { return }
                await self.unregisterInstallationIfReady()
            }
        }
    }

    private func handleDelete(inboxId: String) async throws {
        // Ensure backend unregister occurs while we're still authorized/ready
        if case .ready = _state {
            await unregisterInstallationIfReady()
        }
        _state = .deleting
        try await inboxWriter.deleteInbox(inboxId: inboxId)
        enqueueAction(.stop)
    }

    private func handleStop() throws {
        _state = .stopping
        removeObservers()
        _state = .uninitialized
    }

    // MARK: - Helpers

    private func createXmtpClient(signingKey: SigningKey,
                                  options: ClientOptions) async throws -> any XMTPClientProvider {
        Logger.info("Creating XMTP client...")
        let client = try await Client.create(account: signingKey, options: options)
        cacheInboxId(inboxId: client.inboxID, for: signingKey.identity)
        Logger.info("XMTP Client created.")
        return client
    }

    private func buildXmtpClient(identity: PublicIdentity,
                                 options: ClientOptions) async throws -> any XMTPClientProvider {
        Logger.info("Building XMTP client...")
        let client = try await Client.build(
            publicIdentity: identity,
            options: options,
            inboxId: cachedInboxId(for: identity)
        )
        Logger.info("XMTP Client built.")
        return client
    }

    private func authorizeConvosBackend(client: any XMTPClientProvider) async throws -> any ConvosAPIClientProtocol {
        Logger.info("Retrieving installation ID and Firebase App Check token...")
        let installationId = client.installationId
        let inboxId = client.inboxId
        let firebaseAppCheckToken = Secrets.FIREBASE_APP_CHECK_TOKEN
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

    private func refreshUserAndProfile(
        client: any XMTPClientProvider,
        apiClient: any ConvosAPIClientProtocol
    ) async throws {
        Logger.info("Authorization succeeded, fetching user and profile")
        async let user = try apiClient.getUser()
        async let profile = try apiClient.getProfile(inboxId: client.inboxId)
        try await inboxWriter.storeInbox(
            inboxId: client.inboxId,
            type: inbox.type,
            provider: inbox.provider,
            providerId: inbox.providerId,
            user: await user,
            profile: await profile
        )
    }

    // MARK: - InboxId Cache

    private func cachedInboxId(for identity: PublicIdentity) -> String? {
        UserDefaults.standard.string(forKey: "cachedInboxId-\(identity.identifier)")
    }

    private func cacheInboxId(inboxId: String, for identity: PublicIdentity) {
        UserDefaults.standard.set(inboxId, forKey: "cachedInboxId-\(identity.identifier)")
    }

    // MARK: - User Creation

    private func createUser(
        displayName: String?,
        client: any XMTPClientProvider,
        apiClient: any ConvosAPIClientProtocol
    ) async throws -> ConvosAPI.CreatedUserResponse {
        let requestBody: ConvosAPI.CreateUserRequest = .init(
            userId: inbox.providerId,
            userType: .onDevice,
            device: .current(),
            identity: .init(identityAddress: inbox.signingKey.identity.identifier,
                            xmtpId: client.inboxId,
                            xmtpInstallationId: client.installationId),
            profile: .init(
                name: displayName,
                username: nil,
                description: nil,
                avatar: nil
            )
        )
        return try await apiClient.createUser(requestBody)
    }

    private func generateUsername(
        apiClient: any ConvosAPIClientProtocol,
        from displayName: String,
        maxRetries: Int = 5
    ) async throws -> String {
        let base = displayName
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()

        let baseUsername = base.isEmpty ? "convos_user" : base

        for i in 0...maxRetries {
            let candidate: String
            if i == 0 {
                candidate = baseUsername
            } else {
                let numDigits = Int(pow(2.0, Double(i - 1)))
                let min = Int(pow(10.0, Double(numDigits - 1)))
                let max = Int(pow(10.0, Double(numDigits))) - 1
                let randomNumber = Int.random(in: min...max)
                candidate = "\(baseUsername)\(randomNumber)"
            }
            do {
                let check = try await apiClient.checkUsername(candidate)
                if !check.taken {
                    return candidate
                }
            } catch {
                Logger.warning("Username check failed for \(candidate): \(error)")
            }
        }

        let random = UUID().uuidString.prefix(10).lowercased()
        return "\(baseUsername)\(random)"
    }
}

// MARK: - Push Token Update

extension InboxStateMachine {
    private func registerForegroundObserver() {
        willEnterForegroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                await self.handleForegroundForPushTokenUpdate()
            }
        }
    }

    private func currentDeviceId() async -> String {
        await MainActor.run { DeviceInfo.deviceIdentifier }
    }

    private func expectedApnsEnvString() -> String {
        environment.apnsEnvironment == .sandbox ? "sandbox" : "production"
    }

    private func storedDeviceToken() -> String? {
        NotificationProcessor.shared.getStoredDeviceToken()
    }

    private func userIdForCurrentInbox() -> String { inbox.providerId }

    nonisolated private func handleForegroundForPushTokenUpdate() async {
        // Hop back to the actor to read state and call the actor-isolated updater
        await self.updateIfReady()
    }

    private func updateIfReady() async {
        guard case let .ready(result) = _state else { return }
        // If the system prompt hasn't been shown yet, request now (app is foregrounding)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            await requestNotificationAuthorizationIfNeeded()
        }
        await registerForNotificationsIfNeeded(client: result.client, apiClient: result.apiClient)
    }

    private func registerForNotificationsIfNeeded(client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) async {
        guard let token = NotificationProcessor.shared.getStoredDeviceToken(), !token.isEmpty else { return }
        let deviceId = await currentDeviceId()
        let identityId = client.inboxId
        let installationId = client.installationId
        do {
            try await apiClient.registerForNotifications(deviceId: deviceId,
                                                         pushToken: token,
                                                         identityId: identityId,
                                                         xmtpInstallationId: installationId)
            Logger.info("Registered notifications mapping for deviceId=\(deviceId), installationId=\(installationId)")
        } catch {
            Logger.error("Failed to register notifications mapping: \(error)")
        }
    }

    private func unsubscribeIfReady(conversationId: String) async {
        guard case let .ready(result) = _state else { return }
        let topic = conversationId.xmtpGroupTopicFormat
        do {
            try await result.apiClient.unsubscribeFromTopics(installationId: result.client.installationId, topics: [topic])
            Logger.info("Unsubscribed from topic: \(topic)")
        } catch {
            Logger.error("Failed to unsubscribe from topic \(topic): \(error)")
        }
    }

    private func unregisterInstallationIfReady() async {
        guard case let .ready(result) = _state else { return }
        do {
            try await result.apiClient.unregisterInstallation(xmtpInstallationId: result.client.installationId)
            Logger.info("Unregistered installation: \(result.client.installationId)")
        } catch {
            Logger.error("Failed to unregister installation: \(error)")
        }
    }

    private func requestNotificationAuthorizationIfNeeded() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            // APNS registration is performed via registerForRemoteNotificationsAlways()
            _ = granted
        } catch {
            Logger.warning("Notification authorization failed: \(error)")
        }
    }

    // Always call registerForRemoteNotifications to get a device token even if alerts aren't authorized yet.
    // This allows silent/background capabilities and ensures we have a token to send to backend.
    private func registerForRemoteNotificationsAlways() async {
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    private func removeObservers() {
        if let pushTokenObserver { NotificationCenter.default.removeObserver(pushTokenObserver) }
        if let conversationUnsubscribeObserver { NotificationCenter.default.removeObserver(conversationUnsubscribeObserver) }
        if let unregisterInstallationObserver { NotificationCenter.default.removeObserver(unregisterInstallationObserver) }
        if let willEnterForegroundObserver { NotificationCenter.default.removeObserver(willEnterForegroundObserver) }
        pushTokenObserver = nil
        conversationUnsubscribeObserver = nil
        unregisterInstallationObserver = nil
        willEnterForegroundObserver = nil
    }
}
