import Combine
import Foundation
import XMTPiOS

class ConvosSigningKey: SigningKey {
    typealias Signer = (String) async throws -> XMTPiOS.SignedData

    let publicIdentifier: String
    let chainId: Int64?
    let signer: Signer
    private(set) var signature: String?

    init(publicIdentifier: String, chainId: Int64?, signer: @escaping Signer) {
        self.publicIdentifier = publicIdentifier
        self.chainId = chainId
        self.signer = signer
    }

    var identity: XMTPiOS.PublicIdentity {
        .init(kind: .ethereum, identifier: publicIdentifier)
    }

    var type: SignerType {
        .SCW
    }

    func sign(_ message: String) async throws -> XMTPiOS.SignedData {
        let signatureData = try await signer(message)
        signature = signatureData.rawData.hexEncodedString()
        return signatureData
    }
}

enum ConvosSigningKeyError: Error {
    case missingPublicIdentifier, missingChainId, nilDataWhenSigningMessage
}

extension ConvosSDK.User {
    var signingKey: ConvosSigningKey {
        get throws {
            guard let publicIdentifier = publicIdentifier else {
                throw ConvosSigningKeyError.missingPublicIdentifier
            }
            guard let chainId = chainId else {
                throw ConvosSigningKeyError.missingChainId
            }
            return ConvosSigningKey(publicIdentifier: publicIdentifier, chainId: chainId) { message in
                guard let data = try await self.sign(message: message) else {
                    throw ConvosSigningKeyError.nilDataWhenSigningMessage
                }
                return .init(rawData: data)
            }
        }
    }
}

private enum MessagingError: Error {
    case notAuthenticated
    case notInitialized
}

final actor MessagingService: ConvosSDK.MessagingServiceProtocol {
    private let authService: ConvosSDK.AuthServiceProtocol
    private let messagesSubject: PassthroughSubject<[ConvosSDK.Message], Never> = .init()
    private var xmtpClient: XMTPiOS.Client?
    private let keychainService: KeychainService<DatabaseKey> = .init()
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
        guard let _ = authService.currentUser else {
            throw MessagingError.notAuthenticated
        }
        // Initialize XMTP client with user's address
    }

    func stop() async {
        if let user = authService.currentUser {
            do {
                Logger.info("Deleting database key for user \(user.id)")
                try keychainService.deleteDatabaseKey(for: user)
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
//        guard let client = xmtpClient else {
//            throw MessagingError.notInitialized
//        }
        // Implement XMTP message sending
    }

    nonisolated func messages(for address: String) -> AnyPublisher<[ConvosSDK.Message], Never> {
        messagesSubject.eraseToAnyPublisher()
    }

    // MARK: - Private

    private func fetchOrCreateDatabaseKey(for user: ConvosSDK.User) async throws -> DatabaseKey {
        if let key = try self.keychainService.retrieveKey(for: user) {
            return key
        } else {
            let key = DatabaseKey.generate(for: user)
            try await self.keychainService.save(DatabaseKey.generate(for: user))
            return key
        }
    }

    private func initializeXmtpClient(for user: ConvosSDK.User) async throws -> ConvosSigningKey? {
        Logger.info("Initializing XMTP client...")
        guard xmtpClient == nil else {
            Logger.warning("Attempted to initialize XMTP when one exists, exiting...")
            return nil
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
        return signingKey
    }

    private func authorizeConvosBackend(signature: String) async throws {
        guard let installationId = xmtpClient?.installationID,
              let xmtpId = xmtpClient?.inboxID else {
            throw InitializationError.xmtpClientMissingRequiredValuesForAuth
        }
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
                            let result = try await self.initializeXmtpClient(for: user)
                            guard let signingKey = result,
                                let signature = signingKey.signature else {
                                Logger.error("No signature found from XMTP Client, failed to auth with convos backend")
                                return
                            }
                            do {
                                _ = try await self.authorizeConvosBackend(signature: signature)
                            } catch {
                                Logger.error("Failed authorizing Convos backend.")
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
