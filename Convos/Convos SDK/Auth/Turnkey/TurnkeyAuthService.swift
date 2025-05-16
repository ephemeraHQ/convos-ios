import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Shared
import TurnkeySDK

extension Notification.Name {
    static let PasskeyManagerModalSheetCanceled: Notification.Name = Notification.Name(
        "PasskeyManagerModalSheetCanceledNotification")
    static let PasskeyManagerError: Notification.Name = Notification.Name("PasskeyManagerErrorNotification")
    static let PasskeyRegistrationCompleted: Notification.Name = Notification.Name(
        "PasskeyRegistrationCompletedNotification")
    static let PasskeyRegistrationFailed: Notification.Name = Notification.Name("PasskeyRegistrationFailedNotification")
    static let PasskeyRegistrationCanceled: Notification.Name = Notification.Name(
        "PasskeyRegistrationCanceledNotification")
    static let PasskeyAssertionCompleted: Notification.Name = Notification.Name(
        "PasskeyAssertionCompletedNotification")
}

enum TurnkeyAuthServiceError: Error {
    case failedFindingPasskeyPresentationAnchor,
         uninitializedTurnkeyClient,
         failedReturningCredential,
         failedCreatingSubOrganization
}

final class TurnkeyAuthService: ConvosSDK.AuthServiceProtocol {
    private var client: TurnkeyClient?
    private var authState: ConvosSDK.AuthServiceState = .notReady
    private let apiClient: ConvosAPIClient
    private var passkeyRegistrationTask: Task<Void, Never>?

    var state: ConvosSDK.AuthServiceState {
        return authState
    }

    var currentUser: ConvosSDK.User? {
        return nil
    }

    private var passkeyRegistration: PasskeyManager?
    private var displayName: String?

    init() {
        guard let apiBaseURL = URL(string: Secrets.CONVOS_API_BASE_URL) else {
            fatalError("Failed constructing API base URL")
        }
        self.apiClient = .init(baseURL: apiBaseURL)
        startObservingPasskeyNotifications()
    }

    deinit {
        stopObservingPasskeyNotifications()
    }

    // MARK: Public

    func prepare() async throws {
        Task { @MainActor in
            let presentationAnchor = try presentationAnchor()
            client = TurnkeyClient(rpId: Secrets.API_RP_ID,
                                   presentationAnchor: presentationAnchor)
            authState = .unauthorized
        }
    }

    func signIn() async throws {
        guard let client = client else {
            throw TurnkeyAuthServiceError.uninitializedTurnkeyClient
        }

        do {
            let loggedInClient = try await client.login(organizationId: Secrets.TURNKEY_PUBLIC_ORGANIZATION_ID)
            print("Logged in as: \(loggedInClient)")
        } catch {
            Logger.error("Error signing in with Turnkey: \(error)")
        }
    }

    func register(displayName: String) async throws {
        self.displayName = displayName
        Task { @MainActor in
            let presentationAnchor = try presentationAnchor()
            passkeyRegistration = PasskeyManager(rpId: Secrets.API_RP_ID,
                                                 presentationAnchor: presentationAnchor)
            passkeyRegistration?.registerPasskey(email: displayName)
        }
    }

    func signOut() async throws {
        // Clear the client and reset state
        client = nil
        authState = .unauthorized
    }

    func authStatePublisher() -> AnyPublisher<ConvosSDK.AuthServiceState, Never> {
        // Create a publisher that emits the current auth state
        return Just(authState).eraseToAnyPublisher()
    }

    // MARK: - Private

    func presentationAnchor() throws -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            throw TurnkeyAuthServiceError.failedFindingPasskeyPresentationAnchor
        }

        return window
    }

    // MARK: - Passkey Notifications

    private func startObservingPasskeyNotifications() {
        // Add observers for passkey registration notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePasskeyRegistrationCompleted),
            name: .PasskeyRegistrationCompleted,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePasskeyRegistrationFailed),
            name: .PasskeyRegistrationFailed,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePasskeyRegistrationCanceled),
            name: .PasskeyRegistrationCanceled,
            object: nil
        )
    }

    private func stopObservingPasskeyNotifications() {
        NotificationCenter.default.removeObserver(self, name: .PasskeyRegistrationCompleted, object: nil)
        NotificationCenter.default.removeObserver(self, name: .PasskeyRegistrationFailed, object: nil)
        NotificationCenter.default.removeObserver(self, name: .PasskeyRegistrationCanceled, object: nil)
    }

    @objc private func handlePasskeyRegistrationCompleted(_ notification: Notification) {
        guard let result = notification.userInfo?["result"] as? PasskeyRegistrationResult else {
            return
        }

        guard let displayName = displayName else {
            return
        }

        let ephemeralPrivateKey = P256.KeyAgreement.PrivateKey()
        let publicKey = ephemeralPrivateKey.publicKey

        guard let apiPublicKey = try? publicKey.toString(
            representation: PublicKeyRepresentation.x963),
              let apiPublicKeyCompressed = try? publicKey.toString(
                representation: PublicKeyRepresentation.compressed
              ),
        let apiPrivateKey = try? ephemeralPrivateKey.toString(
            representation: PrivateKeyRepresentation.raw) else {
            Logger.error("Missing api keys")
            return
        }

        let authClient = TurnkeyClient(
            apiPrivateKey: apiPrivateKey,
            apiPublicKey: apiPublicKeyCompressed
        )

        passkeyRegistrationTask = Task {
            do {
                let expirationSeconds: Int = 3600
                let result = try await sendCreateSubOrgRequest(
                    ephemeralPublicKey: apiPublicKeyCompressed,
                    passkeyRegistrationResult: result,
                    displayName: displayName
                )

                Logger.info("Private key: \(apiPrivateKey) Public key: \(apiPublicKey)")

                guard let result else {
                    throw TurnkeyAuthServiceError.failedCreatingSubOrganization
                }

                Logger.info("Create sub organization result from Convos backend: \(result)")

                let sessionResponse = try await authClient.createReadWriteSession(
                    organizationId: result.subOrgId,
                    targetPublicKey: apiPublicKey,
                    userId: nil,
                    apiKeyName: "session-key",
                    expirationSeconds: String(expirationSeconds)
                )

                switch sessionResponse {
                case let .undocumented(status, payload):
                    if let body = payload.body {
                        // Convert the HTTPBody to a string
                        let bodyString = try await String(collecting: body, upTo: .max)
                        print("bodyString: \(bodyString)")
                    }
                    print("status: \(status) payload: \(payload)")
                case .ok(let output):
                    print("output: \(output)")
                }
                Logger.info("Session response: \(sessionResponse)")

                let responseBody = try sessionResponse.ok.body.json
                guard let result = responseBody.activity.result.createReadWriteSessionResultV2 else {
                    throw NSError(
                        domain: "TurnkeyClient",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Missing createReadWriteSessionResultV2"]
                    )
                }
                let organizationId = result.organizationId
                let userId = result.userId

                guard try await TurnkeySessionManager.shared.saveSession(
                    userId: userId,
                    organizationId: organizationId,
                    encryptedBundle: result.credentialBundle,
                    ephemeralPrivateKey: ephemeralPrivateKey
                ) != nil else {
                    Logger.error("Failed saving session")
                    return
                }

                Logger.info("Finished registering with Turnkey")
            } catch {
                Logger.error("Error registering with Turnkey: \(error)")
            }
        }
    }

    @objc private func handlePasskeyRegistrationFailed(_ notification: Notification) {
        guard let error = notification.userInfo?["error"] as? PasskeyRegistrationError else {
            return
        }

        // Handle passkey registration failure
        Logger.error("Error handling passkey registration: \(error)")
    }

    @objc private func handlePasskeyRegistrationCanceled(_ notification: Notification) {
        // Handle passkey registration cancellation
        Logger.info("Passkey Registration canceled")
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
