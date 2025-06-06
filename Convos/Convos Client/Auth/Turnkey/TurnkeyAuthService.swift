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

        let digest = Data(message.utf8)
        let digestHex = digest.toHexString()
        do {
            let result = try await turnkey.signRawPayload(
                signWith: walletAddress,
                payload: digestHex,
                encoding: .PAYLOAD_ENCODING_HEXADECIMAL,
                hashFunction: .HASH_FUNCTION_SHA256
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

    var currentUser: User? {
        return nil
    }

    init() {
        let authStatePublisher: AnyPublisher<AuthServiceState, Never> = turnkey
            .$user
            .removeDuplicates(by: { lhs, rhs in
                lhs?.id == rhs?.id
            })
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

    // MARK: - Passkey Notifications

//    @objc private func handlePasskeyRegistrationCompleted(_ notification: Notification) {
//        guard let result = notification.userInfo?["result"] as? PasskeyRegistrationResult else {
//            return
//        }
//
//        guard let displayName = displayName else {
//            return
//        }
//
//        let ephemeralPrivateKey = P256.KeyAgreement.PrivateKey()
//        let publicKey = ephemeralPrivateKey.publicKey
//
//        guard let apiPublicKey = try? publicKey.toString(
//            representation: PublicKeyRepresentation.x963),
//              let apiPublicKeyCompressed = try? publicKey.toString(
//                representation: PublicKeyRepresentation.compressed
//              ),
//        let apiPrivateKey = try? ephemeralPrivateKey.toString(
//            representation: PrivateKeyRepresentation.raw) else {
//            Logger.error("Missing api keys")
//            return
//        }
//
//        let authClient = TurnkeyClient(
//            apiPrivateKey: apiPrivateKey,
//            apiPublicKey: apiPublicKeyCompressed
//        )
//
//        passkeyRegistrationTask = Task {
//            do {
//                let expirationSeconds: Int = 3600
//                let result = try await sendCreateSubOrgRequest(
//                    ephemeralPublicKey: apiPublicKeyCompressed,
//                    passkeyRegistrationResult: result,
//                    displayName: displayName
//                )
//
//                Logger.info("Private key: \(apiPrivateKey) Public key: \(apiPublicKey)")
//
//                guard let result else {
//                    throw TurnkeyAuthServiceError.failedCreatingSubOrganization
//                }
//
//                Logger.info("Create sub organization result from Convos backend: \(result)")
//
//                let sessionResponse = try await authClient.createReadWriteSession(
//                    organizationId: result.subOrgId,
//                    targetPublicKey: apiPublicKey,
//                    userId: nil,
//                    apiKeyName: "session-key",
//                    expirationSeconds: String(expirationSeconds)
//                )
//
//                switch sessionResponse {
//                case let .undocumented(status, payload):
//                    if let body = payload.body {
//                        // Convert the HTTPBody to a string
//                        let bodyString = try await String(collecting: body, upTo: .max)
//                        print("bodyString: \(bodyString)")
//                    }
//                    print("status: \(status) payload: \(payload)")
//                case .ok(let output):
//                    print("output: \(output)")
//                }
//                Logger.info("Session response: \(sessionResponse)")
//
//                let responseBody = try sessionResponse.ok.body.json
//                guard let result = responseBody.activity.result.createReadWriteSessionResultV2 else {
//                    throw NSError(
//                        domain: "TurnkeyClient",
//                        code: 1,
//                        userInfo: [NSLocalizedDescriptionKey: "Missing createReadWriteSessionResultV2"]
//                    )
//                }
//                let organizationId = result.organizationId
//                let userId = result.userId
//
//                guard try await TurnkeySessionManager.shared.saveSession(
//                    userId: userId,
//                    organizationId: organizationId,
//                    encryptedBundle: result.credentialBundle,
//                    ephemeralPrivateKey: ephemeralPrivateKey
//                ) != nil else {
//                    Logger.error("Failed saving session")
//                    return
//                }
//
//                Logger.info("Finished registering with Turnkey")
//            } catch {
//                Logger.error("Error registering with Turnkey: \(error)")
//            }
//        }
//    }
//
//    @objc private func handlePasskeyRegistrationFailed(_ notification: Notification) {
//        guard let error = notification.userInfo?["error"] as? PasskeyRegistrationError else {
//            return
//        }
//
//        // Handle passkey registration failure
//        Logger.error("Error handling passkey registration: \(error)")
//    }
//
//    @objc private func handlePasskeyRegistrationCanceled(_ notification: Notification) {
//        // Handle passkey registration cancellation
//        Logger.info("Passkey Registration canceled")
//    }

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
