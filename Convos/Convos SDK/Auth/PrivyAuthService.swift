import Combine
import Foundation
import PasskeyAuth
import PrivySDK

extension Data {
    struct HexEncodingOptions: OptionSet {
        let rawValue: Int
        static let upperCase: HexEncodingOptions = .init(rawValue: 1 << 0)
    }

    func hexEncodedString(options: HexEncodingOptions = []) -> String {
        let format = options.contains(.upperCase) ? "%02hhX" : "%02hhx"
        return self.map { String(format: format, $0) }.joined()
    }

    init?(hexString: String) {
        var hex = hexString
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }

        guard hex.count.isMultiple(of: 2) else { return nil }

        var newData = Data()
        var index = hex.startIndex

        for _ in 0..<(hex.count / 2) {
            let nextIndex = hex.index(index, offsetBy: 2)
            if let b = UInt8(hex[index..<nextIndex], radix: 16) {
                newData.append(b)
            } else {
                return nil
            }
            index = nextIndex
        }

        self = newData
    }
}

// privy auth state
extension AuthState {
    var authServiceState: ConvosSDK.AuthServiceState {
        switch self {
        case .authenticated(let user):
            return .authorized(ConvosUser(privyUser: user))
        case .unauthenticated:
            return .unauthorized
        case .notReady:
            return .notReady
        default:
            return .unknown
        }
    }
}

private class PrivyJWTProvider {
    private let keychainService: KeychainService<ConvosKeychainItem> = .init()

    var jwt: String? {
        get {
            do {
                return try keychainService.retrieve(.jwt)
            } catch {
                Logger.error("Error retrieving JWT token from keychain: \(error.localizedDescription)")
            }

            return nil
        }
        set {
            do {
                if let newValue = newValue {
                    try keychainService.save(newValue, for: .jwt)
                } else {
                    try keychainService.delete(.jwt)
                }
            } catch {
                Logger.error("Error setting or deleting JWT token from keychain: \(error.localizedDescription)")
            }
        }
    }
}

final class PrivyAuthService: ConvosSDK.AuthServiceProtocol {
    var state: ConvosSDK.AuthServiceState {
        return privy.authState.authServiceState
    }

    var currentUser: ConvosSDK.User? {
        guard case .authenticated(let user) = privy.authState else {
            return nil
        }
        return ConvosUser(privyUser: user)
    }

    var messagingService: any ConvosSDK.MessagingServiceProtocol {
        MessagingService(authService: self)
    }

    private let privy: Privy
    private let passkeyAuth: PasskeyAuth
    private let jwtProvider: PrivyJWTProvider

    init() {
        guard let passkeyBaseURL = URL(string: Secrets.API_BASE_URL),
              let configuration = try? PasskeyConfiguration(
            baseURL: passkeyBaseURL,
            rpID: Secrets.API_RP_ID,
            endpoints: PasskeyEndpoints(
                registerChallenge: "/auth/challenge/register",
                loginChallenge: "/auth/challenge/login",
                registerPasskey: "/auth/register-passkey",
                loginPasskey: "/auth/login-passkey"
            )
        ) else {
            fatalError("Error initializing PasskeyAuth configuration")
        }
        self.passkeyAuth = PasskeyAuth(configuration: configuration)

        let jwtProvider = PrivyJWTProvider()
        self.jwtProvider = jwtProvider
        Logger.info("Initialized PrivyJWTProvider with token length: \(jwtProvider.jwt?.count ?? 0)")
        let authConfig = PrivyLoginWithCustomAuthConfig {
            Logger.info("Returning JWT for Privy authentication with length: \(jwtProvider.jwt?.count ?? 0)")
            return jwtProvider.jwt
        }
        let config = PrivyConfig(
            appId: Secrets.PRIVY_APP_ID,
            appClientId: Secrets.PRIVY_APP_CLIENT_ID,
            loggingConfig: .init(
                logLevel: .verbose
            ),
            customAuthConfig: authConfig
        )
        self.privy = PrivySdk.initialize(config: config)
    }

    // MARK: Public

    func prepare() async {
        Task { @MainActor in
            Logger.info("Awaiting Privy...")
            await privy.awaitReady()
            Logger.info("Privy ready")
            await setupPasskeyPresentationProvider()
        }
    }

    func setupPasskeyPresentationProvider() async {
        let presentationProvider = await PasskeyPresentationProvider()
        await passkeyAuth.setPresentationContextProvider(presentationProvider)
    }

    func signIn() async throws {
        let response = try await passkeyAuth.loginWithPasskey()
        jwtProvider.jwt = response.token

        do {
            let user = try await self.privy.customJwt.loginWithCustomAccessToken()
            Logger.info("Signed in with Privy user: \(user)")
            do {
                let wallet = try await user.createEthereumWallet(allowAdditional: false)
                Logger.info("Created Ethereum wallet: \(wallet) for signed in: \(user)")
            } catch {
                Logger.info("Creating embedded wallet failed, assuming one exists")
            }
        } catch {
            Logger.error("Error logging in with Privy: \(error)")
            throw error
        }
    }

    func register(displayName: String) async throws {
        let response = try await passkeyAuth.registerPasskey(displayName: displayName)
        jwtProvider.jwt = response.token
        do {
            let user = try await privy.customJwt.loginWithCustomAccessToken()
            Logger.info("Registered \(displayName) with Privy for user: \(user)")
            do {
                let wallet = try await user.createEthereumWallet(allowAdditional: false)
                Logger.info("Created ethereum wallet: \(wallet) for registered user: \(user)")
            } catch {
                Logger.info("Creating embedded wallet failed during registration")
            }
        } catch {
            Logger.info("Failed Privy login while registering \(displayName)")
            throw error
        }
    }

    func signOut() async throws {
        jwtProvider.jwt = nil
        if case .authenticated(let user) = privy.authState {
            user.logout()
            Logger.info("Signed out with auth state: \(privy.authState)")
        }
    }

    func authStatePublisher() -> AnyPublisher<ConvosSDK.AuthServiceState, Never> {
        return privy.authStatePublisher
            .map { $0.authServiceState }
            .eraseToAnyPublisher()
    }
}
