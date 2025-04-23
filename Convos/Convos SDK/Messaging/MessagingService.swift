import Combine
import Foundation
import XMTPiOS

public extension ConvosSDK {
    protocol Message {
        var id: String { get }
        var content: String { get }
        var sender: User { get }
        var timestamp: Date { get }
    }

    protocol MessagingServiceProtocol {
        func start() async throws
        func stop()
        func sendMessage(to address: String, content: String) async throws
        func messages(for address: String) -> AnyPublisher<[Message], Never>
    }
}

struct MockMessage: ConvosSDK.Message {
    var id: String
    var content: String
    var sender: any ConvosSDK.User
    var timestamp: Date

    static func message(_ content: String) -> MockMessage {
        .init(
            id: UUID().uuidString,
            content: content,
            sender: MockUser(),
            timestamp: Date()
        )
    }
}

class MockMessagingService: ConvosSDK.MessagingServiceProtocol {
    private var messagesSubject: CurrentValueSubject<[ConvosSDK.Message], Never> = .init([])

    func start() async throws {
    }

    func stop() {
    }

    func sendMessage(to address: String, content: String) async throws {
        messagesSubject.send([MockMessage.message(content)])
    }

    func messages(for address: String) -> AnyPublisher<[any ConvosSDK.Message], Never> {
        messagesSubject.eraseToAnyPublisher()
    }
}

struct ConvosSigningKey: SigningKey {
    typealias Signer = (String) async throws -> XMTPiOS.SignedData

    let publicIdentifier: String
    let chainId: Int64?
    let signer: Signer

    var identity: XMTPiOS.PublicIdentity {
        .init(kind: .ethereum, identifier: publicIdentifier)
    }

    var type: SignerType {
        .SCW
    }

    func sign(_ message: String) async throws -> XMTPiOS.SignedData {
        return try await signer(message)
    }
}

enum ConvosSigningKeyError: Error {
    case missingPublicIdentifier, missingChainId, nilDataWhenSigningMessage
}

public extension ConvosSDK.User {
    var signingKey: SigningKey {
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

private struct DatabaseKey: KeychainItemProtocol {
    let account: String
    let value: String

    var valueData: Data? {
        Data(base64Encoded: value)
    }

    static func generate(for user: ConvosSDK.User) -> DatabaseKey {
        let databaseKey = Data((0 ..< 32)
            .map { _ in UInt8.random(in: UInt8.min ... UInt8.max) })
        let value = databaseKey.base64EncodedString()
        return .init(account: user.id, value: value)
    }
}

extension KeychainService where T == DatabaseKey {
    func save(_ databaseKey: DatabaseKey) async throws {
        try save(databaseKey.value, for: databaseKey)
    }

    func retrieveKey(for user: ConvosSDK.User) throws -> DatabaseKey? {
        let account = user.id
        guard let value = try retrieve(service: DatabaseKey.service, account: account) else {
            return nil
        }
        return .init(account: account, value: value)
    }

    func delete(for user: ConvosSDK.User) throws {
        try delete(service: DatabaseKey.service, account: user.id)
    }
}

final actor MessagingService: ConvosSDK.MessagingServiceProtocol {
    private let authService: ConvosSDK.AuthServiceProtocol
    private let messagesSubject: PassthroughSubject<[ConvosSDK.Message], Never> = .init()
    private var xmtpClient: XMTPiOS.Client?
    private let keychainService: KeychainService<DatabaseKey> = .init()
    private var cancellables: Set<AnyCancellable> = []

    enum InitializationError: Error {
        case failedDecryptingDatabaseKey
    }

    init(authService: ConvosSDK.AuthServiceProtocol) {
        self.authService = authService
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

    nonisolated func stop() {
        Task {
            if let user = await authService.currentUser {
                do {
                    try await keychainService.delete(for: user)
                } catch {
                    Logger.error("Failed deleting database key for user \(user.id): \(error.localizedDescription)")
                }
            }
            await setXmtpClient(nil)
        }
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
        Logger.info("Sending signing key to XMTP Client with chainId: \(String(describing: signingKey.chainId))")
        xmtpClient = try await Client.create(account: signingKey, options: options)
    }

    private func setXmtpClient(_ client: XMTPiOS.Client?) {
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
                        } catch {
                            Logger.error("Failed initializing XMTP Client: \(error.localizedDescription)")
                        }
                    default:
                        break
                    }
                }
            })
            .store(in: &cancellables)
    }
}

private enum MessagingError: Error {
    case notAuthenticated
    case notInitialized
}

private struct ConvosMessage: ConvosSDK.Message {
    let xmtpMessage: XMTPiOS.DecodedMessage
    let sender: ConvosSDK.User

    var id: String { xmtpMessage.id }
    var content: String { (try? xmtpMessage.body) ?? "" }
    var timestamp: Date { xmtpMessage.sentAt }
}
