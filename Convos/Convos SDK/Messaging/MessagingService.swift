import Combine
import Foundation
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
    case xmtpInitialized(ConvosSDK.AuthorizedResultType, PrivateKey)
    case backendAuthorized
}

extension XMTPiOS.Member: ConvosSDK.User {
    public var avatarURL: URL? {
        nil
    }

    public var id: String {
        ""
    }

    public var name: String {
        ""
    }

    public var username: String? {
        nil
    }

    public var displayName: String? {
        nil
    }

    public var walletAddress: String? {
        nil
    }

    public var chainId: Int64? {
        0
    }

    public func sign(message: String) async throws -> Data? {
        nil
    }
}

struct XMTPiOSMember: ConvosSDK.User {
    var id: String
    var name: String
    var username: String?
    var displayName: String?
    var walletAddress: String?
    var chainId: Int64?
    var avatarURL: URL?

    func sign(message: String) async throws -> Data? {
        nil
    }
}

extension XMTPiOS.DecodedMessage: ConvosSDK.RawMessageType {
    public var content: String {
        ""
    }

    public var sender: any ConvosSDK.User {
        XMTPiOSMember(id: "", name: "")
    }

    public var timestamp: Date {
        Date()
    }

    public var replies: [any ConvosSDK.RawMessageType] {
        []
    }
}

extension XMTPiOS.Conversation: ConvosSDK.ConversationType {
    public var lastMessage: (any ConvosSDK.RawMessageType)? {
        get async throws {
            try await lastMessage()
        }
    }

    public var otherParticipant: (any ConvosSDK.User)? {
        get async throws {
            try await members().first
        }
    }

    public var isPinned: Bool {
        false
    }

    public var isUnread: Bool {
        false
    }

    public var isRequest: Bool {
        false
    }

    public var isMuted: Bool {
        false
    }

    public var timestamp: Date {
        createdAt
    }

    public var amount: Double? {
        nil
    }
}

final actor MessagingService: ConvosSDK.MessagingServiceProtocol {
    private let authService: ConvosSDK.AuthServiceProtocol
    private var xmtpClient: XMTPiOS.Client?
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
    private let stateSubject: CurrentValueSubject<ConvosSDK.MessagingServiceState, Never> = .init(.uninitialized)

    init(authService: ConvosSDK.AuthServiceProtocol) {
        self.authService = authService
        guard let apiBaseURL = URL(string: Secrets.CONVOS_API_BASE_URL) else {
            fatalError("Failed constructing API base URL")
        }
        self.apiClient = .init(baseURL: apiBaseURL)
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

    // MARK: - Conversations

    func conversations() async throws -> [ConvosSDK.ConversationType] {
        guard let xmtpClient else { return [] }
        return try await xmtpClient.conversations.list()
    }

    func conversationsStream() async -> AsyncThrowingStream<any ConvosSDK.ConversationType, any Error> {
        guard let xmtpClient else { return .init {
            nil
        } }
        let baseStream = await xmtpClient.conversations.stream()
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await conversation in baseStream {
                        continuation.yield(conversation as any ConvosSDK.ConversationType)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Messages

    nonisolated
    func messages(for address: String) -> AnyPublisher<[ConvosSDK.RawMessageType], Never> {
        Just([]).eraseToAnyPublisher()
    }

    func loadInitialMessages() async -> [ConvosSDK.RawMessageType] {
        []
    }

    func loadPreviousMessages() async -> [ConvosSDK.RawMessageType] {
        []
    }

    // MARK: -

    nonisolated func messagingStatePublisher() -> AnyPublisher<ConvosSDK.MessagingServiceState, Never> {
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
                case (.initializing, let .xmtpInitialized(result, privateKey)):
                    try await authorizeConvosBackend(from: result,
                                                     privateKey: privateKey)
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
        let privateKey = try PrivateKey(authorizedResult.privateKeyData)
        try await initializeXmtpClient(with: authorizedResult.privateKeyData,
                                       signingKey: privateKey)
        await processAction(.xmtpInitialized(authorizedResult, privateKey))
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

    private func createUser(from result: ConvosSDK.RegisteredResultType, privateKey: PrivateKey) async throws {
        let userId = UUID().uuidString
        let username = try await generateUsername(from: result.displayName)
        let xmtpId = xmtpClient?.inboxID
        let xmtpInstallationId = xmtpClient?.installationID
        let requestBody: ConvosAPIClient.CreateUserRequest = .init(
            turnkeyUserId: userId,
            device: .current(),
            identity: .init(turnkeyAddress: privateKey.walletAddress,
                            xmtpId: xmtpId,
                            xmtpInstallationId: xmtpInstallationId),
            profile: .init(name: result.displayName,
                           username: username,
                           description: nil,
                           avatar: nil)
        )
        let createdUser = try await apiClient.createUser(requestBody)
        Logger.info("Created user: \(createdUser)")
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

    // MARK: - Messaging

    func sendMessage(to address: String, content: String) async throws -> [any ConvosSDK.RawMessageType] {
        guard xmtpClient != nil else {
            throw MessagingServiceError.notInitialized
        }
        // Implement XMTP message sending
        return []
    }

    // MARK: - Helpers

    private func initializeXmtpClient(with databaseKey: Data,
                                      signingKey: SigningKey) async throws {
        Logger.info("Initializing XMTP client...")
        guard xmtpClient == nil else {
            throw MessagingServiceError.xmtpClientAlreadyInitialized
        }
        let options = ClientOptions(dbEncryptionKey: databaseKey)
        Logger.info("Initializing XMTP client...")
        xmtpClient = try await Client.create(account: signingKey, options: options)
        Logger.info("XMTP Client initialized, returning signing key.")
    }

    private func authorizeConvosBackend(from result: ConvosSDK.AuthorizedResultType,
                                        privateKey: PrivateKey) async throws {
        guard let client = xmtpClient else {
            throw MessagingServiceError.xmtpClientMissingRequiredValuesForAuth
        }

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
        if let registeredResult = result as? ConvosSDK.RegisteredResultType {
            Logger.info("Creating user from registeredResult: \(registeredResult)")
            try await createUser(from: registeredResult,
                                 privateKey: privateKey)
        } else {
            let user = try await apiClient.getUser()
            Logger.info("Authenticated with Convos backend: \(result) user: \(user)")
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
