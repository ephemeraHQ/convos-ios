import Combine
import Foundation
import GRDB
import XMTPiOS

private enum MessagingServiceError: Error {
    case notAuthenticated
    case notInitialized
    case xmtpClientAlreadyInitialized
    case xmtpClientMissingRequiredValuesForAuth
}

private enum MessagingServiceState {
    case uninitialized
    case initializing
    case authorizing
    case ready
    case stopping
    case error(Error)
}

private enum MessagingServiceAction {
    case start
    case stop
    case xmtpInitialized(Client, ConvosSDK.AuthorizedResultType)
    case backendAuthorized
}

final actor MessagingService: ConvosSDK.MessagingServiceProtocol {
    private let authService: ConvosSDK.AuthServiceProtocol
    private let userWriter: UserWriter
    private let syncingManager: SyncingManagerProtocol
    private let databaseReader: any DatabaseReader
    private let databaseWriter: any DatabaseWriter

    nonisolated
    var clientPublisher: AnyPublisher<(any XMTPClientProvider)?, Never> {
        clientSubject.eraseToAnyPublisher()
    }
    nonisolated
    private let clientSubject: CurrentValueSubject<(any XMTPClientProvider)?, Never> = .init(nil)
    private var xmtpClient: XMTPiOS.Client? {
        didSet {
            clientSubject.send(xmtpClient)
        }
    }
    private var cancellables: Set<AnyCancellable> = []
    private let apiClient: ConvosAPIClient
    private var _state: ConvosSDK.MessagingServiceState = .uninitialized {
        didSet {
            stateSubject.send(_state)
        }
    }
    private var currentTask: Task<Void, Never>?

    nonisolated
    var state: ConvosSDK.MessagingServiceState {
        stateSubject.value
    }
    nonisolated
    private let stateSubject: CurrentValueSubject<ConvosSDK.MessagingServiceState, Never> = .init(
        .uninitialized
    )

    private var cachedInboxId: String? {
        get {
            UserDefaults.standard.string(forKey: "cachedInboxId")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "cachedInboxId")
        }
    }

    init(authService: ConvosSDK.AuthServiceProtocol,
         databaseWriter: any DatabaseWriter,
         databaseReader: any DatabaseReader) {
        self.authService = authService
        self.userWriter = UserWriter(databaseWriter: databaseWriter)
        self.apiClient = ConvosAPIClient.shared
        self.syncingManager = SyncingManager(databaseWriter: databaseWriter,
                                             apiClient: apiClient)
        self.databaseReader = databaseReader
        self.databaseWriter = databaseWriter
        Task {
            await observeAuthState()
        }
    }

    func start() async throws {
        await processAction(.start)
    }

    func stop() async {
        await processAction(.stop)
    }

    // MARK: User

    nonisolated
    func userRepository() -> any UserRepositoryProtocol {
        UserRepository(dbReader: databaseReader)
    }

    // MARK: Profile Search

    nonisolated
    func profileSearchRepository() -> any ProfileSearchRepositoryProtocol {
        ProfileSearchRepository(apiClient: ConvosAPIClient.shared)
    }

    // MARK: Conversations

    nonisolated
    func conversationsRepository() -> any ConversationsRepositoryProtocol {
        ConversationsRepository(dbReader: databaseReader)
    }

    nonisolated
    func conversationRepository(for conversationId: String) -> any ConversationRepositoryProtocol {
        ConversationRepository(conversationId: conversationId,
                               dbReader: databaseReader)
    }

    // MARK: Getting/Sending Messages

    nonisolated
    func messagesRepository(for conversationId: String) -> any MessagesRepositoryProtocol {
        MessagesRepository(dbReader: databaseReader,
                           conversationId: conversationId)
    }

    nonisolated
    func messageWriter(for conversationId: String) -> any OutgoingMessageWriterProtocol {
        OutgoingMessageWriter(clientPublisher: clientPublisher,
                              databaseWriter: databaseWriter,
                              conversationId: conversationId)
    }

    // MARK: -

    nonisolated
    func messagingStatePublisher() -> AnyPublisher<ConvosSDK.MessagingServiceState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    // MARK: - State Machine

    private func processAction(_ action: MessagingServiceAction) async {
        currentTask?.cancel()
        currentTask = Task {
            do {
                switch (_state, action) {
                case (.uninitialized, .start):
                    try await handleStart()
                case (.initializing, let .xmtpInitialized(client, result)):
                    syncingManager.start(with: client)
                    try await authorizeConvosBackend(client: client,
                                                     authResult: result)
                case (.authorizing, .backendAuthorized):
                    try handleBackendAuthorized()
                case (.ready, .stop), (.error, .stop):
                    try handleStop()
                case (.error, .start):
                    try await handleStart()
                case (.uninitialized, .stop):
                    break
                default:
                    Logger.warning("Invalid MessagingService state transition: \(_state) -> \(action)")
                }
            } catch {
                Logger.error(
                    "MessagingService failed state transition \(_state) -> \(action): \(error.localizedDescription)"
                )
                _state = .error(error)
            }
        }
    }

    private func handleStart() async throws {
        guard let authorizedResult = authService.state.authorizedResult else {
            _state = .error(MessagingServiceError.notAuthenticated)
            return
        }

        _state = .initializing
        let client: Client
        let clientOptions = ClientOptions(dbEncryptionKey: authorizedResult.databaseKey)
        if authorizedResult is ConvosSDK.RegisteredResultType {
            client = try await createXmtpClient(signingKey: authorizedResult.signingKey,
                                                options: clientOptions)
        } else {
            client = try await buildXmtpClient(identity: authorizedResult.signingKey.identity,
                                               options: clientOptions)
        }
        await processAction(.xmtpInitialized(client, authorizedResult))
    }

    private func handleBackendAuthorized() throws {
        _state = .ready
    }

    private func handleStop() throws {
        _state = .stopping
        try cleanupResources()
        _state = .uninitialized
    }

    private func cleanupResources() throws {
        if let client = xmtpClient {
            Logger.info("Deleting local XMTP database")
            try client.deleteLocalDatabase()
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

    private func createUser(from result: ConvosSDK.RegisteredResultType,
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
                                        authResult: ConvosSDK.AuthorizedResultType) async throws {
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
        if let registeredResult = authResult as? ConvosSDK.RegisteredResultType {
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
                            Logger.info("MessagingService starting from auth state changing to authorized")
                            try await self.start()
                        } catch {
                            Logger.error("Auth state change failed to start messaging: \(error.localizedDescription)")
                        }
                    case .unauthorized:
                        Logger.info("MessagingService stopping from auth state changing to unauthorized")
                        await self.stop()
                    default:
                        break
                    }
                }
            })
            .store(in: &cancellables)
    }
}
