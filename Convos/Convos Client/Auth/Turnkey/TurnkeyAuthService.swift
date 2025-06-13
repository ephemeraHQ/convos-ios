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

extension SessionUser {
    var databaseKey: Data {
        get throws {
            try TurnkeyDatabaseKeyStore.shared.databaseKey(for: id)
        }
    }
}

struct TurnkeySigningKey: SigningKey {
    var identity: XMTPiOS.PublicIdentity {
        guard let walletAddress = primaryWalletAddress else {
            Logger.error("Error returning identity, no wallet address found")
            return .init(kind: .ethereum, identifier: "")
        }
        return .init(kind: .ethereum, identifier: walletAddress)
    }

    private let turnkey: TurnkeyContext = .shared
    private let user: SessionUser

    init(user: SessionUser) {
        self.user = user
    }

    private var primaryWalletAddress: String? {
        guard let wallet = user.wallets.first else {
            Logger.error("Failed returning wallet address: No wallet found")
            return nil
        }

        guard let account = wallet.accounts.first else {
            Logger.error("Failed returning wallet address: No account found")
            return nil
        }

        return account.address
    }

    func sign(_ message: String) async throws -> SignedData {
        guard let walletAddress = primaryWalletAddress else {
            Logger.error("Failed signing message: No wallet address")
            return .init(rawData: Data())
        }

        let prefix = "\u{19}Ethereum Signed Message:\n\(message.utf8.count)"
        let fullMessage = prefix + message
        let digest = Data(fullMessage.utf8).sha3(.keccak256)
        let digestString = digest.hexEncodedString()
        do {
            let result = try await turnkey.signRawPayload(
                signWith: walletAddress,
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
         failedStampingLogin
}

final class TurnkeyAuthService: AuthServiceProtocol {
    struct TurnkeyRegisteredResult: AuthServiceRegisteredResultType {
        let displayName: String
        let signingKey: SigningKey
        let databaseKey: Data
    }

    struct TurnkeyAuthResult: AuthServiceResultType {
        let signingKey: SigningKey
        let databaseKey: Data
    }

    private var authState: CurrentValueSubject<AuthServiceState, Never> = .init(.notReady)
    private let apiClient: ConvosAPIClient = .shared
    private let turnkey: TurnkeyContext = .shared
    private var passkeyRegistrationTask: Task<Void, Never>?
    private let defaultSessionExpiration: String = "900" // seconds
    private var cancellables: Set<AnyCancellable> = []

    enum AuthFlowType {
        case passive, login, register(displayName: String)
    }

    private var authFlowType: AuthFlowType = .passive

    var state: AuthServiceState {
        return authState.value
    }

    init() {
        let authStatePublisher: AnyPublisher<AuthServiceState, Never> = turnkey
            .$user
//            .removeDuplicates(by: { lhs, rhs in
//                lhs?.id == rhs?.id
//            })
            .map { [weak self] user in
                guard let self else { return .unknown }

                defer {
                    authFlowType = .passive
                }

                guard let user else {
                    return .unauthorized
                }

                let signingKey = TurnkeySigningKey(user: user)
                do {
                    let databaseKey = try user.databaseKey
                    switch authFlowType {
                    case .passive, .login:
                        let result = TurnkeyAuthResult(
                            signingKey: signingKey,
                            databaseKey: databaseKey
                        )
                        return .authorized(result)
                    case .register(let displayName):
                        let result = TurnkeyRegisteredResult(
                            displayName: displayName,
                            signingKey: signingKey,
                            databaseKey: databaseKey
                        )
                        return .registered(result)
                    }
                } catch {
                    Logger.error("Error retrieving database key: \(error)")
                    return .unauthorized
                }
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

    func prepare() async throws {
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
            rp: RelyingParty(id: Secrets.API_RP_ID, name: "Convos"),
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
        // Clear the client and reset state
//        authState = .unauthorized
    }

    var authStatePublisher: AnyPublisher<AuthServiceState, Never> {
        authState.eraseToAnyPublisher()
    }

    // MARK: - Private

    private func stampLoginAndCreateSession(
        anchor: ASPresentationAnchor,
        organizationId: String,
        expiresInSeconds: String,
        client: TurnkeyClient? = nil
    ) async throws {
        let client = client ?? TurnkeyClient(
            rpId: Secrets.API_RP_ID,
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
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            throw TurnkeyAuthServiceError.failedFindingPasskeyPresentationAnchor
        }

        return window
    }

    // MARK: - Convos Backend

    func sendCreateSubOrgRequest(
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
}
