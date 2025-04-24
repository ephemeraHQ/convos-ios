import Combine
import Foundation
import XMTPiOS

private enum MessagingServiceError: Error {
    case notAuthenticated
    case notInitialized
    case initializationFailed(Error)
    case invalidAddress
    case networkError(Error)
    case stoppingServiceFailed(Error)
}

final actor MessagingService: ConvosSDK.MessagingServiceProtocol {
    private let authService: ConvosSDK.AuthServiceProtocol
    private var xmtpClient: XMTPiOS.Client?
    private let keychainService: KeychainService<ConvosKeychainItem> = .init()
    private var cancellables: Set<AnyCancellable> = []
    private let apiClient: ConvosAPIClient
    private var state: ConvosSDK.MessagingServiceState = .uninitialized

    enum InitializationError: Error {
        case failedDecryptingDatabaseKey
        case xmtpClientMissingRequiredValuesForAuth
    }

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
        guard case .uninitialized = state else {
            Logger.warning("Attempted to start service in non-uninitialized state: \(state)")
            return
        }

        state = .initializing
        do {
            if let user = authService.currentUser {
                try await setupMessagingService(for: user)
                state = .ready
            } else {
                state = .error(MessagingServiceError.notAuthenticated)
            }
        } catch {
            state = .error(MessagingServiceError.initializationFailed(error))
            throw error
        }
    }

    func stop() async {
        guard case .ready = state else {
            Logger.warning("Attempted to stop service in un-ready state: \(state)")
            return
        }

        do {
            if let user = authService.currentUser {
                Logger.info("Deleting database key for user \(user.id)")
                try keychainService.delete(.xmtpDatabaseKey)
            }

            Logger.info("Deleting local XMTP database")
            try xmtpClient?.deleteLocalDatabase()
        } catch {
            Logger.error("Failed deleting local XMTP database for user: \(error.localizedDescription)")
            state = .error(MessagingServiceError.stoppingServiceFailed(error))
        }
        setXmtpClient(nil)
        state = .uninitialized
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
            Logger.warning("Attempted to initialize XMTP when one exists, exiting...")
            return
        }
        let key = try await fetchOrCreateDatabaseKey(for: user)
        guard let encryptionKey = key.valueData else {
            throw InitializationError.failedDecryptingDatabaseKey
        }
        let options = ClientOptions(dbEncryptionKey: encryptionKey)
        let signingKey = try user.signingKey
        Logger.info("Initializing XMTP client...")
        xmtpClient = try await Client.create(account: signingKey, options: options)
        Logger.info("XMTP Client initialized, returning signing key.")
    }

    private func authorizeConvosBackend() async throws {
        guard let client = xmtpClient else {
            throw InitializationError.xmtpClientMissingRequiredValuesForAuth
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

    private func setupMessagingService(for user: ConvosSDK.User) async throws {
        try await initializeXmtpClient(for: user)
        _ = try await authorizeConvosBackend()
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
