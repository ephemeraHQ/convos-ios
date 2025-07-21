import Combine
import Foundation
import XMTPiOS

private extension AppEnvironment {
    var xmtpEnv: XMTPEnvironment {
        switch self {
        case .local, .tests: return .local
        case .dev, .otrDev: return .dev
        case .production: return .production
        }
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

typealias InboxReadyResult = (
    client: any XMTPClientProvider,
    apiClient: any ConvosAPIClientProtocol
)

actor InboxStateMachine {
    enum Action {
        case authorize,
             register(String),
             clientInitialized(any XMTPClientProvider),
             clientRegistered(any XMTPClientProvider, String),
             authorized(InboxReadyResult),
             stop
    }

    enum State {
        case uninitialized,
             initializing,
             authorizing,
             registering,
             ready(InboxReadyResult),
             stopping,
             error(Error)
    }

    // MARK: -

    let inbox: any AuthServiceInboxType
    private let inboxWriter: any InboxWriterProtocol
    private let environment: AppEnvironment
    private let clientOptions: ClientOptions
    private let syncingManager: any SyncingManagerProtocol

    private var _state: State = .uninitialized {
        didSet {
            stateSubject.send(_state)
        }
    }

    private var currentTask: Task<Void, Never>?
    private var actionQueue: [Action] = []
    private var isProcessing: Bool = false

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
        environment: AppEnvironment
    ) {
        self.inbox = inbox
        self.inboxWriter = inboxWriter
        self.syncingManager = syncingManager
        self.environment = environment
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
    }

    // MARK: - Public

    func authorize() {
        enqueueAction(.authorize)
    }

    func register(displayName: String) {
        enqueueAction(.register(displayName))
    }

    func stop() {
        enqueueAction(.stop)
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
            case (.authorizing, let .authorized((client, apiClient))),
                (.registering, let .authorized((client, apiClient))):
                try handleAuthorized(client: client, apiClient: apiClient)
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
            Logger.error("Error building client, trying create: \(error)")
            client = try await createXmtpClient(
                signingKey: inbox.signingKey,
                options: clientOptions
            )
        }
        enqueueAction(.clientInitialized(client))
    }

    private func handleRegister(displayName: String) async throws {
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
        try await refreshUserAndProfile(client: client, apiClient: apiClient)
        enqueueAction(.authorized((client, apiClient)))
    }

    private func handleClientRegistered(_ client: any XMTPClientProvider, displayName: String) async throws {
        _state = .authorizing
        Logger.info("Authorizing backend for registration...")
        let apiClient = try await authorizeConvosBackend(client: client)
        _state = .registering
        Logger.info("Creating user with display name '\(displayName)'...")
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
        enqueueAction(.authorized((client, apiClient)))
    }

    private func handleAuthorized(client: any XMTPClientProvider, apiClient: any ConvosAPIClientProtocol) throws {
        _state = .ready((client, apiClient))
        syncingManager.start(with: client, apiClient: apiClient)
    }

    private func handleStop() throws {
        _state = .stopping
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
        displayName: String,
        client: any XMTPClientProvider,
        apiClient: any ConvosAPIClientProtocol
    ) async throws -> ConvosAPI.CreatedUserResponse {
        let username = try await generateUsername(apiClient: apiClient, from: displayName)
        let requestBody: ConvosAPI.CreateUserRequest = .init(
            turnkeyUserId: inbox.providerId,
            device: .current(),
            identity: .init(turnkeyAddress: inbox.signingKey.identity.identifier,
                            xmtpId: client.inboxId,
                            xmtpInstallationId: client.installationId),
            profile: .init(name: displayName,
                           username: username,
                           description: nil,
                           avatar: nil)
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
