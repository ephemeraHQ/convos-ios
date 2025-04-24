import Combine
import Foundation
import XMTPiOS

private enum MessagingServiceError: Error {
    case notAuthenticated
    case notInitialized
    case failedDecryptingDatabaseKey
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

final actor MessagingService: ConvosSDK.MessagingServiceProtocol {
    private let authService: ConvosSDK.AuthServiceProtocol
    private var xmtpClient: XMTPiOS.Client?
    private let keychainService: KeychainService<ConvosKeychainItem> = .init()
    private var cancellables: Set<AnyCancellable> = []
    private let apiClient: ConvosAPIClient
    private var state: ConvosSDK.MessagingServiceState = .uninitialized
    private var currentTask: Task<Void, Never>?

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

    private func processAction(_ action: MessagingServiceAction) async {
        currentTask?.cancel()
        currentTask = Task {
            do {
                switch (state, action) {
                case (.uninitialized, .start):
                    try await handleStart()
                case (.initializing, .xmtpInitialized):
                    try await handleXmtpInitialized()
                case (.authorizing, .backendAuthorized):
                    try await handleBackendAuthorized()
                case (.ready, .stop):
                    try await handleStop()
                case (.error, .start):
                    try await handleStart()
                default:
                    Logger.warning("Invalid MessagingService state transition: \(state) -> \(action)")
                }
            } catch {
                Logger.error("Failed processing action \(action): \(error.localizedDescription)")
                state = .error(error)
            }
        }
    }

    private func handleStart() async throws {
        guard let user = authService.currentUser else {
            state = .error(MessagingServiceError.notAuthenticated)
            return
        }

        state = .initializing
        try await initializeXmtpClient(for: user)
        await processAction(.xmtpInitialized)
    }

    private func handleXmtpInitialized() async throws {
        state = .authorizing
        _ = try await authorizeConvosBackend()
        await processAction(.backendAuthorized)
    }

    private func handleBackendAuthorized() async throws {
        state = .ready
    }

    private func handleStop() async throws {
        state = .stopping
        try await cleanupResources()
        state = .uninitialized
    }

    private func cleanupResources() async throws {
        if let user = authService.currentUser {
            Logger.info("Deleting database key for user \(user.id)")
            try keychainService.delete(.xmtpDatabaseKey)
        }

        Logger.info("Deleting local XMTP database")
        try xmtpClient?.deleteLocalDatabase()
        setXmtpClient(nil)
    }

    func sendMessage(to address: String, content: String) async throws {
        guard xmtpClient != nil else {
            throw MessagingServiceError.notInitialized
        }
        // Implement XMTP message sending
    }

    nonisolated func messages(for address: String) -> AnyPublisher<[ConvosSDK.Message], Never> {
        // TODO: Implement proper message streaming from XMTP client
        Just([]).eraseToAnyPublisher()
    }

    // MARK: - Private

    private func fetchOrCreateDatabaseKey(for user: ConvosSDK.User) async throws -> DatabaseKey {
        if let key = try self.keychainService.retrieve(.xmtpDatabaseKey) {
            return .init(value: key)
        } else {
            let key = DatabaseKey.generate(for: user)
            try self.keychainService.save(key.value, for: .xmtpDatabaseKey)
            return key
        }
    }

    private func initializeXmtpClient(for user: ConvosSDK.User) async throws {
        Logger.info("Initializing XMTP client...")
        guard xmtpClient == nil else {
            throw MessagingServiceError.xmtpClientAlreadyInitialized
        }
        let key = try await fetchOrCreateDatabaseKey(for: user)
        guard let encryptionKey = key.valueData else {
            throw MessagingServiceError.failedDecryptingDatabaseKey
        }
        let options = ClientOptions(dbEncryptionKey: encryptionKey)
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
                            try await self.start()
                        } catch {
                            Logger.error("Auth state change failed to start messaging: \(error.localizedDescription)")
                        }
                    case .unauthorized:
                        await self.stop()
                    default:
                        break
                    }
                }
            })
            .store(in: &cancellables)
    }
}

private struct ConvosMessage: ConvosSDK.Message {
    private let xmtpMessage: XMTPiOS.DecodedMessage
    let sender: ConvosSDK.User

    var id: String { xmtpMessage.id }
    var content: String { (try? xmtpMessage.body) ?? "" }
    var timestamp: Date { xmtpMessage.sentAt }
}
