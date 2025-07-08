import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import TurnkeyCrypto
import TurnkeyHttp
import TurnkeyPasskeys
import TurnkeySwift
import XMTPiOS

fileprivate extension SignRawPayloadResult {
    var rawSignature: Data? {
        let rData = r.hexToData
        let sData = s.hexToData
        guard rData.count <= 32, sData.count <= 32,
            let vValue = UInt8(v, radix: 16) ?? UInt8(v) // try hex or decimal
        else {
            return nil
        }

        // Pad r and s to 32 bytes if needed
        let rPadded = Data(repeating: 0, count: 32 - rData.count) + rData
        let sPadded = Data(repeating: 0, count: 32 - sData.count) + sData

        return rPadded + sPadded + Data([vValue])
    }

    var signedData: SignedData {
        guard let rawSignature else {
            Logger.error("Failed getting raw signature from SignRawPayloadResult")
            return SignedData(rawData: Data())
        }
        return SignedData(rawData: rawSignature)
    }
}

extension SessionUser.UserWallet.WalletAccount: @retroactive SigningKey {
    private var turnkey: TurnkeyContext { .shared }

    public var identity: XMTPiOS.PublicIdentity {
        return .init(kind: .ethereum, identifier: address)
    }

    var databaseKey: Data {
        get throws {
            return try TurnkeyDatabaseKeyStore.shared.databaseKey(for: address)
        }
    }

    public func sign(_ message: String) async throws -> SignedData {
        let prefix = "\u{19}Ethereum Signed Message:\n\(message.utf8.count)"
        let fullMessage = prefix + message
        let digest = Data(fullMessage.utf8).sha3(.keccak256)
        let digestString = digest.hexEncodedString()
        do {
            let result = try await turnkey.signRawPayload(
                signWith: address,
                payload: digestString,
                encoding: .PAYLOAD_ENCODING_HEXADECIMAL,
                hashFunction: .HASH_FUNCTION_NO_OP
            )
            return result.signedData
        } catch {
            Logger.error("Error signing message: \(error)")
            throw error
        }
    }
}

enum TurnkeyAuthServiceError: Error {
    case failedFindingPasskeyPresentationAnchor,
         failedCreatingSubOrganization,
         failedStampingLogin,
         walletMissing,
         walletAddressNotFound,
         walletAccountMissing,
         unauthorizedAccess
}

extension SessionUser {
    var defaultWallet: SessionUser.UserWallet? {
        wallets.first(
            where: { $0.name == TurnkeyAuthService.Constant.defaultWalletName }
        )
    }

    var otrWallet: SessionUser.UserWallet? {
        wallets.first(
            where: { $0.name == TurnkeyAuthService.Constant.otrWalletName }
        )
    }
}

fileprivate extension AuthState {
    var authServiceState: AuthServiceState {
        switch self {
        case .loading, .authenticated:
            return .notReady
        case .unAuthenticated:
            return .unauthorized
        }
    }
}

final class TurnkeyAuthService: AuthServiceProtocol {
    let accountsService: (any AuthAccountsServiceProtocol)?
    private let environment: AppEnvironment
    private var authState: CurrentValueSubject<AuthServiceState, Never> = .init(.notReady)
    private let apiClient: any ConvosAPIBaseProtocol
    private let turnkey: TurnkeyContext = .shared
    private let defaultSessionExpiration: String = "\(60 * 24 * 60 * 60)"  // 60 days
    private var cancellables: Set<AnyCancellable> = []

    enum AuthFlowType {
        case passive, login, register(displayName: String)
    }

    private var authFlowType: AuthFlowType = .passive

    var state: AuthServiceState {
        return authState.value
    }

    init(environment: AppEnvironment) {
        self.accountsService = TurnkeyAccountsService(
            turnkey: turnkey,
            environment: environment
        )
        self.environment = environment
        self.apiClient = ConvosAPIClientFactory.client(environment: environment)
        let authStatePublisher: AnyPublisher<AuthServiceState, Never> = turnkey
            .$user
//            .removeDuplicates(by: { lhs, rhs in
//                lhs?.id == rhs?.id
//            })
            .map { [weak self] user in
                guard let self else { return .unknown }

                guard turnkey.authState != .loading else {
                    return .notReady
                }

                return authState(for: user)
            }
            .eraseToAnyPublisher()
        authStatePublisher
            .sink { [weak self] state in
                guard let self else { return }
                authState.send(state)
            }
            .store(in: &cancellables)
    }

    // MARK: Public

    func prepare() throws {
        authState.send(turnkey.authState.authServiceState)
        Task {
            try await turnkey.refreshSession()
        }
    }

    func signIn() async throws {
        authFlowType = .login
        let anchor = try await presentationAnchor()
        try await stampLoginAndCreateSession(
            anchor: anchor,
            organizationId: Secrets.TURNKEY_PUBLIC_ORGANIZATION_ID,
            expiresInSeconds: defaultSessionExpiration
        )
    }

    func register(displayName: String) async throws {
        authFlowType = .register(displayName: displayName)
        let anchor = try await presentationAnchor()
        let registration = try await createPasskey(
            user: PasskeyUser(
                id: UUID().uuidString,
                name: displayName,
                displayName: displayName
            ),
            rp: RelyingParty(id: environment.relyingPartyIdentifier, name: "Convos"),
            presentationAnchor: anchor
        )

        let (_, publicKeyCompressed, privateKey) = TurnkeyCrypto.generateP256KeyPair()

        guard let result = try await sendCreateSubOrgRequest(
            ephemeralPublicKey: publicKeyCompressed,
            passkeyRegistrationResult: registration,
            displayName: displayName
        ) else {
            throw TurnkeyAuthServiceError.failedCreatingSubOrganization
        }

        let ephemeralClient = TurnkeyClient(
            apiPrivateKey: privateKey,
            apiPublicKey: publicKeyCompressed
        )

        try await stampLoginAndCreateSession(
            anchor: anchor,
            organizationId: result.subOrgId,
            expiresInSeconds: defaultSessionExpiration,
            client: ephemeralClient
        )
    }

    func signOut() async throws {
        turnkey.clearSession()
    }

    var authStatePublisher: AnyPublisher<AuthServiceState, Never> {
        authState.eraseToAnyPublisher()
    }

    // MARK: - Private

    private func authState(for user: SessionUser?) -> AuthServiceState {
        defer {
            authFlowType = .passive
        }

        guard let user else {
            let migration = ReactNativeMigration(environment: environment)
            return migration.needsMigration ? .migrating(migration) : .unauthorized
        }

        guard let wallet = user.defaultWallet else {
            Logger.error("Default Wallet not found for Turnkey user, unauthorized")
            return .unauthorized
        }

        if user.wallets.count > 1 {
            Logger.warning("Multiple wallets found for Turnkey user, using default")
        }

        // if we're coming from the RN app, only one account exists
        if wallet.accounts.count == 1, let account = wallet.accounts.first {
            let userIdentifier = account.identity.identifier
            if case let .migrating(migration) = state {
                do {
                    try migration.performMigration(for: userIdentifier)
                } catch {
                    Logger.error("Failed performing migration for user \(userIdentifier): \(error)")
                    return .migrating(migration)
                }
            }
        }

        do {
            switch authFlowType {
            case .passive, .login:
                let inboxes = try wallet.accounts.map { account in
                    AuthServiceInbox(
                        type: .standard,
                        provider: .external(.turnkey),
                        providerId: account.id,
                        signingKey: account,
                        databaseKey: try account.databaseKey
                    )
                }
                let result = AuthServiceResult(inboxes: inboxes)
                return .authorized(result)
            case .register(let displayName):
                guard let account = wallet.accounts.first else {
                    throw TurnkeyAuthServiceError.walletAccountMissing
                }
                if wallet.accounts.count > 1 {
                    Logger.warning("Multiple accounts found for Turnkey user, using the first one")
                }
                let databaseKey = try account.databaseKey
                let result = AuthServiceRegisteredResult(
                    displayName: displayName,
                    inbox: AuthServiceInbox(
                        type: .standard,
                        provider: .external(.turnkey),
                        providerId: account.id,
                        signingKey: account,
                        databaseKey: databaseKey
                    )
                )
                return .registered(result)
            }
        } catch {
            Logger.error("Error retrieving database key: \(error)")
            return .unauthorized
        }
    }

    private func stampLoginAndCreateSession(
        anchor: ASPresentationAnchor,
        organizationId: String,
        expiresInSeconds: String,
        client: TurnkeyClient? = nil
    ) async throws {
        let client = client ?? TurnkeyClient(
            rpId: environment.relyingPartyIdentifier,
            presentationAnchor: anchor
        )

        let publicKey = try turnkey.createKeyPair()

        do {
            let resp = try await client.stampLogin(
                organizationId: organizationId,
                publicKey: publicKey,
                expirationSeconds: expiresInSeconds,
                invalidateExisting: true
            )

            guard
                case let .json(body) = resp.body,
                let jwt = body.activity.result.stampLoginResult?.session
            else {
                throw TurnkeyAuthServiceError.failedStampingLogin
            }

            try await turnkey.createSession(jwt: jwt)
        } catch let error as TurnkeyRequestError {
            Logger.error("Failed to stamp login code \(error.statusCode ?? 0): \(error.fullMessage)")
            throw error
        }
    }

    @MainActor
    func presentationAnchor() throws -> ASPresentationAnchor {
        do {
            return try TurnkeyPresentationAnchorProvider.presentationAnchor()
        } catch TurnkeyPresentationAnchorError.failedFindingPasskeyPresentationAnchor {
            throw TurnkeyAuthServiceError.failedFindingPasskeyPresentationAnchor
        }
    }

    // MARK: - Convos Backend

    private func sendCreateSubOrgRequest(
        ephemeralPublicKey: String,
        passkeyRegistrationResult: PasskeyRegistrationResult,
        displayName: String
    ) async throws -> CreateSubOrganizationResponse? {
        let passkey = Passkey(
            challenge: passkeyRegistrationResult.challenge,
            attestation: PasskeyAttestation(
                credentialId: passkeyRegistrationResult.attestation.credentialId,
                clientDataJson: passkeyRegistrationResult.attestation.clientDataJson,
                attestationObject: passkeyRegistrationResult.attestation.attestationObject,
                transports: [.transportInternal]
            )
        )

        let response = try await apiClient.createSubOrganization(
            ephemeralPublicKey: ephemeralPublicKey,
            passkey: .init(
                challenge: passkey.challenge,
                attestation: passkey.attestation
            )
        )

        return response
    }

    internal enum Constant {
        static var defaultWalletName: String = "Default Wallet"
        static var otrWalletName: String = "OTR Wallet"
    }
}
