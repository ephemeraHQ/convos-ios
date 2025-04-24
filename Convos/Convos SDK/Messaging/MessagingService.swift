import Combine
import Foundation
import XMTPiOS

private enum MessagingError: Error {
    case notAuthenticated
    case notInitialized
}

final actor MessagingService: ConvosSDK.MessagingServiceProtocol {
    private let authService: ConvosSDK.AuthServiceProtocol
    private var xmtpClient: XMTPiOS.Client?
    private let keychainService: KeychainService<ConvosKeychainItem> = .init()
    private var cancellables: Set<AnyCancellable> = []
    private let apiClient: ConvosAPIClient

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
    }

    func stop() async {
        if let user = authService.currentUser {
            do {
                Logger.info("Deleting database key for user \(user.id)")
                try keychainService.delete(.xmtpDatabaseKey)
            } catch {
                Logger.error("Failed deleting database key for user \(user.id): \(error.localizedDescription)")
            }
        }
        do {
            Logger.info("Deleting local XMTP database")
            try xmtpClient?.deleteLocalDatabase()
        } catch {
            Logger.error("Failed deleting local XMTP database for user: \(error.localizedDescription)")
        }
        setXmtpClient(nil)
    }

    func sendMessage(to address: String, content: String) async throws {
        guard xmtpClient != nil else {
            throw MessagingError.notInitialized
        }
        // Implement XMTP message sending
    }

    nonisolated func messages(for address: String) -> AnyPublisher<[ConvosSDK.Message], Never> {
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

    private func observeAuthState() async {
        authService.authStatePublisher()
            .sink(receiveValue: { [weak self] authState in
                Logger.info("Auth state changed from messaging service observer: \(authState)")
                Task {
                    guard let self = self else { return }
                    switch authState {
                    case .authorized(let user):
                        do {
                            try await self.initializeXmtpClient(for: user)
                            
                            guard let client = await self.xmtpClient else {
                                Logger.info("XMTP client nil, skipping auth state change...")
                                return
                            }

                            do {
                                _ = try await self.authorizeConvosBackend()
                            } catch {
                                Logger.error("Failed authorizing Convos backend: \(error.localizedDescription)")
                            }
                        } catch {
                            Logger.error("Failed initializing XMTP Client: \(error.localizedDescription)")
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
