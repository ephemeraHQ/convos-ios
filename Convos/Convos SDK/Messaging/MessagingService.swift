import Combine
import Foundation
import XMTPiOS

private enum MessagingServiceError: Error {
    case notAuthenticated
    case notInitialized
    case xmtpClientAlreadyInitialized
    case xmtpClientMissingRequiredValuesForAuth
}

private enum MessagingServiceAction {
    case start
    case stop
    case xmtpInitialized
    case backendAuthorized
}

private enum MessagingServiceEffect {
    case initializeXmtpClient(ConvosSDK.User)
    case authorizeBackend
    case cleanupResources
    case none
}

extension XMTPiOS.Member: ConvosSDK.User {
    public var id: String {
        ""
    }

    public var name: String {
        ""
    }

    public var publicIdentifier: String? {
        nil
    }

    public var chainId: Int64? {
        0
    }

    public func sign(message: String) async throws -> Data? {
        nil
    }
}

// TODO: Temporary to get around not initializing XMTPiOS.Member
struct XMTPiOSMember: ConvosSDK.User {
    var id: String
    var name: String
    var publicIdentifier: String?
    var chainId: Int64?

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

final actor MessagingService: ConvosSDK.MessagingServiceProtocol {
    nonisolated
    func messages(for address: String) -> AnyPublisher<[XMTPiOS.DecodedMessage], Never> {
        Just([]).eraseToAnyPublisher()
    }

    func loadInitialMessages() async -> [XMTPiOS.DecodedMessage] {
        []
    }

    func loadPreviousMessages() async -> [XMTPiOS.DecodedMessage] {
        []
    }

    typealias RawMessage = XMTPiOS.DecodedMessage

    private let authService: ConvosSDK.AuthServiceProtocol
    private var xmtpClient: XMTPiOS.Client?
    private let keychainService: KeychainService<ConvosKeychainItem> = .init()
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
                case (.initializing, .xmtpInitialized):
                    try await handleXmtpInitialized()
                case (.authorizing, .backendAuthorized):
                    try handleBackendAuthorized()
                case (.ready, .stop), (.error, .stop):
                    try handleStop()
                case (.error, .start):
                    try await handleStart()
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
        guard let user = authService.currentUser else {
            _state = .error(MessagingServiceError.notAuthenticated)
            return
        }

        _state = .initializing
        try await initializeXmtpClient(for: user)
        await processAction(.xmtpInitialized)
    }

    private func handleXmtpInitialized() async throws {
        _state = .authorizing
        _ = try await authorizeConvosBackend()
        await processAction(.backendAuthorized)
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
            Logger.info("Deleting XMTP database key")
            try keychainService.delete(.xmtpDatabaseKey)
            setXmtpClient(nil)
        } else {
            Logger.warning("XMTP Client not initialized, skipping database deletion")
        }
    }

    // MARK: - Messaging

    func sendMessage(to address: String, content: String) async throws -> [XMTPiOS.DecodedMessage] {
        guard xmtpClient != nil else {
            throw MessagingServiceError.notInitialized
        }
        // Implement XMTP message sending
        return []
    }

    nonisolated func messages(for address: String) -> AnyPublisher<[ConvosSDK.RawMessageType], Never> {
        Just([]).eraseToAnyPublisher()
    }

    // MARK: - Helpers

    private func fetchOrCreateDatabaseKey() throws -> DatabaseKey {
        if let key = try self.keychainService.retrieveData(.xmtpDatabaseKey) {
            Logger.info("Found existing XMTP database key: \(key.base64EncodedString())")
            return .init(rawData: key)
        } else {
            let key = try DatabaseKey.generate()
            Logger.info("Generating new XMTP database key: \(key.rawData.base64EncodedString())")
            try self.keychainService.saveData(key.rawData, for: .xmtpDatabaseKey)
            return key
        }
    }

    private func initializeXmtpClient(for user: ConvosSDK.User) async throws {
        Logger.info("Initializing XMTP client...")
        guard xmtpClient == nil else {
            throw MessagingServiceError.xmtpClientAlreadyInitialized
        }
        let key = try fetchOrCreateDatabaseKey()
        let options = ClientOptions(dbEncryptionKey: key.rawData)
        let signingKey = try user.signingKey
        Logger.info("Initializing XMTP client...")
        xmtpClient = try await Client.create(account: signingKey, options: options)
        Logger.info("XMTP Client initialized, returning signing key.")
    }

    private func authorizeConvosBackend() async throws {
        guard let client = xmtpClient else {
            throw MessagingServiceError.xmtpClientMissingRequiredValuesForAuth
        }

        let installationId = client.installationID
        let xmtpId = client.inboxID
        let firebaseAppCheckToken = Secrets.FIREBASE_APP_CHECK_TOKEN
        let signatureData = try client.signWithInstallationKey(message: firebaseAppCheckToken)
        let signature = signatureData.hexEncodedString()

        Logger.info("Attempting to authenticate with Convos backend...")
        let result = try await apiClient.authenticate(xmtpInstallationId: installationId,
                                                      xmtpId: xmtpId,
                                                      xmtpSignature: signature)
        Logger.info("Authenticated with Convos backend: \(result)")
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
                    case .authorized:
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
