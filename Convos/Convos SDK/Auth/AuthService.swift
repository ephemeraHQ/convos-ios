import Combine
import Foundation
import XMTPiOS

public extension ConvosSDK {
    protocol AuthorizedResultType {
        var privateKeyData: Data { get throws }
    }

//    struct AnyAuthorizedResult: AuthorizedResultType {
//        private let _privateKeyData: () throws -> Data
//
//        public init<T: AuthorizedResultType>(_ base: T) {
//            self._privateKeyData = { try base.privateKeyData }
//        }
//
//        public var privateKeyData: Data {
//            get throws { try _privateKeyData() }
//        }
//    }

    enum AuthServiceState {
        case unknown, notReady, authorized(AuthorizedResultType), unauthorized
    }

    protocol AuthServiceProtocol {
        var state: AuthServiceState { get }

        func prepare() async throws

        func signIn() async throws
        func register(displayName: String) async throws
        func signOut() async throws

        func authStatePublisher() -> AnyPublisher<AuthServiceState, Never>
    }
}

extension PrivateKey {
    var walletAddress: String {
        let publicKey = publicKey.secp256K1Uncompressed.bytes
        let publicKeyData =
        publicKey.count == 64 ? publicKey : publicKey[1..<publicKey.count]

        let hash = publicKeyData.sha3(.keccak256)
        let address = hash.subdata(in: 12..<hash.count)
        return "0x" + address.toHex.lowercased()
    }
}

struct MockUser: ConvosSDK.User, ConvosSDK.AuthorizedResultType, Codable {
    var id: String
    var name: String
    var username: String?
    var displayName: String?
    let privateKey: PrivateKey
    var avatarURL: URL?

    var privateKeyData: Data {
        get throws {
            try privateKey.serializedData()
        }
    }

    var chainId: Int64? {
        nil
    }

    var walletAddress: String? {
        privateKey.walletAddress
    }

    enum CodingKeys: String, CodingKey {
        case id, name, privateKeyData
    }

    init(name: String) throws {
        self.id = UUID().uuidString
        self.name = name
        self.privateKey = try PrivateKey.generate()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        let privateKeyData = try container.decode(Data.self, forKey: .privateKeyData)
        self.privateKey = try PrivateKey(privateKeyData)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(privateKey.secp256K1.bytes, forKey: .privateKeyData)
    }

    func sign(message: String) async throws -> Data? {
        return try await privateKey.sign(message).rawData
    }
}

class MockAuthService: ConvosSDK.AuthServiceProtocol {
    enum MockKeychainItem: String, KeychainItemProtocol {
        case mockUser

        var account: String {
            return rawValue
        }
    }

    private let keychain: KeychainService<MockKeychainItem> = .init()
    private var _currentUser: MockUser?

    var currentUser: ConvosSDK.User? {
        _currentUser
    }

    var state: ConvosSDK.AuthServiceState {
        authStateSubject.value
    }

    private var authStateSubject: CurrentValueSubject<ConvosSDK.AuthServiceState, Never> = .init(.unknown)

    init() {
        authStateSubject.send(.unauthorized)
    }

    func prepare() async throws {
        guard let mockUser = try getCurrentUser() else {
            authStateSubject.send(.unauthorized)
            return
        }
        _currentUser = mockUser
        authStateSubject.send(.authorized(mockUser))
    }

    func signIn() async throws {
        guard let mockUser = try getCurrentUser() else {
            return
        }
        _currentUser = mockUser
        authStateSubject.send(.authorized(mockUser))
    }

    func register(displayName: String) async throws {
        let mockUser = try MockUser(name: displayName)
        let encoder = JSONEncoder()
        let data = try encoder.encode(mockUser)
        try keychain.saveData(data, for: .mockUser)
        _currentUser = mockUser
        authStateSubject.send(.authorized(mockUser))
    }

    func signOut() async throws {
        try keychain.delete(.mockUser)
        _currentUser = nil
        authStateSubject.send(.unauthorized)
    }

    func authStatePublisher() -> AnyPublisher<ConvosSDK.AuthServiceState, Never> {
        return authStateSubject.eraseToAnyPublisher()
    }

    private func getCurrentUser() throws -> MockUser? {
        guard let mockUserData = try keychain.retrieveData(.mockUser) else {
            authStateSubject.send(.unauthorized)
            return nil
        }
        let jsonDecoder = JSONDecoder()
        let mockUser = try jsonDecoder.decode(MockUser.self,
                                              from: mockUserData)
        return mockUser
    }
}
