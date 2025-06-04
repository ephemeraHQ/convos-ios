import Combine
import Foundation
import XMTPiOS

private extension MessagingServiceEnvironment {
    var xmtpEnv: XMTPEnvironment {
        switch self {
        case .local: return .local
        case .dev: return .dev
        case .production: return .production
        }
    }

    var isSecure: Bool {
        switch self {
        case .local:
            return false
        default:
            return true
        }
    }
}

private enum MessagingServiceError: Error {
    case notAuthenticated
    case notInitialized
    case xmtpClientAlreadyInitialized
    case xmtpClientMissingRequiredValuesForAuth
}

private enum MessagingServiceAction {
    case start
    case stop
    case xmtpInitialized(Client, AuthServiceResultType)
    case backendAuthorized
}

final actor MessagingServiceStateMachine {
    private let authService: any AuthServiceProtocol
    private let apiClient: any ConvosAPIClientProtocol
    private let userWriter: any UserWriterProtocol
    private let syncingManager: any SyncingManagerProtocol
    private let environment: MessagingServiceEnvironment

    private var cancellables: Set<AnyCancellable> = []

    private var _state: MessagingServiceState = .uninitialized {
        didSet {
            stateSubject.send(_state)
        }
    }

    private var currentTask: Task<Void, Never>?

    private var xmtpClient: XMTPiOS.Client? {
        didSet {
            clientSubject.send(xmtpClient)
        }
    }

    private var cachedInboxId: String? {
        get {
            UserDefaults.standard.string(forKey: "cachedInboxId")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "cachedInboxId")
        }
    }

    // MARK: - Nonisolated

    nonisolated
    var state: MessagingServiceState {
        stateSubject.value
    }

    nonisolated
    private let stateSubject: CurrentValueSubject<MessagingServiceState, Never> = .init(
        .uninitialized
    )

    nonisolated
    var statePublisher: AnyPublisher<MessagingServiceState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    nonisolated
    private let clientSubject: CurrentValueSubject<(any XMTPClientProvider)?, Never> = .init(nil)

    nonisolated
    var clientPublisher: AnyPublisher<(any XMTPClientProvider)?, Never> {
        clientSubject.eraseToAnyPublisher()
    }

    // MARK: - Init

    init(
        authService: any AuthServiceProtocol,
        apiClient: any ConvosAPIClientProtocol,
        userWriter: any UserWriterProtocol,
        syncingManager: any SyncingManagerProtocol,
        environment: MessagingServiceEnvironment
    ) {
        self.authService = authService
        self.apiClient = apiClient
        self.userWriter = userWriter
        self.syncingManager = syncingManager
        self.environment = environment

        Task {
            await observeAuthState()
        }
    }

    // MARK: - Public

    func start() async throws {
        await processAction(.start)
    }

    func stop() async {
        await processAction(.stop)
    }

    // MARK: - Private
    private func processAction(_ action: MessagingServiceAction) async {
        currentTask?.cancel()
        currentTask = Task {
            do {
                switch (_state, action) {
                case (.uninitialized, .start):
                    try await handleStart()
                case (.initializing, let .xmtpInitialized(client, result)):
                    try await handleXMTPInitialized(with: client, authResult: result)
                case (.authorizing, .backendAuthorized):
                    try handleBackendAuthorized()
                case (.ready, .stop), (.error, .stop):
                    try handleStop()
                case (.error, .start):
                    try await handleStart()
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
    }

    private func handleXMTPInitialized(with client: Client,
                                       authResult: AuthServiceResultType) async throws {
        syncingManager.start(with: client)
        try await authorizeConvosBackend(client: client,
                                         authResult: authResult)
    }

    private func handleStart() async throws {
        guard let authorizedResult = authService.state.authorizedResult else {
            _state = .error(MessagingServiceError.notAuthenticated)
            return
        }

        _state = .initializing
        let client: Client
        let clientOptions = ClientOptions(
            api: .init(
                env: environment.xmtpEnv,
                isSecure: environment.isSecure
            ),
            dbEncryptionKey: authorizedResult.databaseKey,
        )
        if authorizedResult is AuthServiceRegisteredResultType {
            client = try await createXmtpClient(signingKey: authorizedResult.signingKey,
                                                options: clientOptions)
        } else {
            client = try await buildXmtpClient(identity: authorizedResult.signingKey.identity,
                                               options: clientOptions)
        }
        Client.register(codec: TextCodec())
        Client.register(codec: ReplyCodec())
        Client.register(codec: ReactionCodec())
        Client.register(codec: AttachmentCodec())
        Client.register(codec: RemoteAttachmentCodec())
        Client.register(codec: GroupUpdatedCodec())
        await processAction(.xmtpInitialized(client, authorizedResult))
    }

    private func handleBackendAuthorized() throws {
        _state = .ready
    }

    private func handleStop() throws {
        _state = .stopping
        syncingManager.stop()
        try cleanupResources()
        _state = .uninitialized
    }

    private func cleanupResources() throws {
        if let client = xmtpClient {
            Logger.info("Deleting local XMTP database")
            let saltPath = client.dbPath + ".sqlcipher_salt"
            if FileManager.default.fileExists(atPath: saltPath) {
                try FileManager.default.removeItem(atPath: saltPath)
            }
            setXmtpClient(nil)
        } else {
            Logger.warning("XMTP Client not initialized, skipping database deletion")
        }
    }

    // MARK: - User Creation

    private func createUser(from result: AuthServiceRegisteredResultType,
                            signingKey: SigningKey) async throws -> ConvosAPI.CreatedUserResponse {
        let userId = UUID().uuidString
        let username = try await generateUsername(from: result.displayName)
        let xmtpId = xmtpClient?.inboxID
        let xmtpInstallationId = xmtpClient?.installationID
        let requestBody: ConvosAPI.CreateUserRequest = .init(
            turnkeyUserId: userId,
            device: .current(),
            identity: .init(turnkeyAddress: signingKey.identity.identifier,
                            xmtpId: xmtpId,
                            xmtpInstallationId: xmtpInstallationId),
            profile: .init(name: result.displayName,
                           username: username,
                           description: nil,
                           avatar: nil)
        )
        return try await apiClient.createUser(requestBody)
    }

    private func generateUsername(from displayName: String, maxRetries: Int = 5) async throws -> String {
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

    // MARK: - Helpers

    private func createXmtpClient(signingKey: SigningKey,
                                  options: ClientOptions) async throws -> Client {
        Logger.info("Atteming to create XMTP client, checking for existing...")
        guard xmtpClient == nil else {
            throw MessagingServiceError.xmtpClientAlreadyInitialized
        }
        Logger.info("Creating XMTP client...")
        let client = try await Client.create(account: signingKey, options: options)
        cachedInboxId = client.inboxID
        xmtpClient = client
        Logger.info("XMTP Client created.")
        return client
    }

    private func buildXmtpClient(identity: PublicIdentity,
                                 options: ClientOptions) async throws -> Client {
        Logger.info("Attempting to build XMTP client, checking for existing...")
        guard xmtpClient == nil else {
            throw MessagingServiceError.xmtpClientAlreadyInitialized
        }
        Logger.info("Building XMTP client...")
        let client = try await Client.build(
            publicIdentity: identity,
            options: options,
            inboxId: cachedInboxId
        )
        xmtpClient = client
        Logger.info("XMTP Client built.")
        return client
    }

    private func authorizeConvosBackend(client: Client,
                                        authResult: AuthServiceResultType) async throws {
        _state = .authorizing
        let installationId = client.installationID
        let xmtpId = client.inboxID
        let firebaseAppCheckToken = Secrets.FIREBASE_APP_CHECK_TOKEN
        let signatureData = try client.signWithInstallationKey(message: firebaseAppCheckToken)
        let signature = signatureData.hexEncodedString()

        Logger.info("Attempting to authenticate with Convos backend...")
        _ = try await apiClient.authenticate(xmtpInstallationId: installationId,
                                             xmtpId: xmtpId,
                                             xmtpSignature: signature)
        if let registeredResult = authResult as? AuthServiceRegisteredResultType {
            Logger.info("Authorization succeeded, creating user from registeredResult: \(registeredResult)")
            let user = try await createUser(from: registeredResult,
                                            signingKey: authResult.signingKey)
            try await userWriter.storeUser(user, inboxId: client.inboxID)
        } else {
            Logger.info("Authorization succeeded, fetching user and profile")
            async let user = try apiClient.getUser()
            async let profile = try apiClient.getProfile(inboxId: client.inboxID)
            try await userWriter.storeUser(await user,
                                           profile: await profile,
                                           inboxId: client.inboxID)
        }
        await processAction(.backendAuthorized)
    }

    private func setXmtpClient(_ client: XMTPiOS.Client?) {
        if client == nil {
            Logger.info("Setting XMTP client to nil")
        } else {
            Logger.info("Setting XMTP client")
        }
        xmtpClient = client
    }

    private func observeAuthState() async {
        authService.authStatePublisher()
            .sink(receiveValue: { [weak self] authState in
                Logger.info("Auth state changed from messaging service observer: \(authState)")
                Task {
                    guard let self = self else { return }
                    switch authState {
                    case .authorized, .registered:
                        do {
                            Logger.info("Starting from auth state changing to authorized")
                            try await self.start()
                        } catch {
                            Logger.error("Auth state change failed to start messaging: \(error.localizedDescription)")
                        }
                    case .unauthorized:
                        Logger.info("Stopping from auth state changing to unauthorized")
                        await self.stop()
                    default:
                        break
                    }
                }
            })
            .store(in: &cancellables)
    }
}
