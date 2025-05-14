import AuthenticationServices
import Combine
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
        
        let session = SessionManager.shared

        do {
            let loggedInClient = try await client.login(organizationId: Secrets.TURNKEY_PUBLIC_ORGANIZATION_ID)
            print("Logged in as: \(loggedInClient)")
        } catch {
            Logger.error("Error signing in with Turnkey: \(error)")
        }
        //        let manager = SecureEnclaveKeyManager()
//        let tag = try manager.createKeypair()
//        let publicKey = try manager.publicKey(tag: tag)
//        let sessionResponse = try await client.createReadWriteSession(
//            organizationId: Secrets.TURNKEY_PUBLIC_ORGANIZATION_ID,
//            targetPublicKey: publicKey.base64EncodedString(),
//            userId: nil,
//            apiKeyName: nil,
//            expirationSeconds: "86400" // 24 hours
//        )

//        if case .ok(let session) = sessionResponse,
//           let credentialBundle = try session.body.json.activity.
//        result.createReadWriteSessionResultV2?.credentialBundle {
//
//
//        } else {
//            throw TurnkeyAuthServiceError.failedFindingPasskeyPresentationAnchor
//        }

//        do {
//            // Get whoami to verify authentication
//            let whoamiResponse = try await client.getWhoami(organizationId: Secrets.TURNKEY_PUBLIC_ORGANIZATION_ID)
//
//            Logger.info("Turnkey Whoami: \(whoamiResponse)")
//            let whoami = try whoamiResponse.ok.body.json
//            Logger.info("Turnkey whoami: \(whoami)")
//
//            // Update auth state and current user
//            //            authState = .authorized(ConvosUser(
//            //                userId: whoami.userId,
//            //                username: whoami.username,
//            //                organizationId: whoami.organizationId,
//            //                organizationName: whoami.organizationName
//            //            ))
//        } catch {
//            Logger.error("Error signing in with Turnkey: \(error)")
//            throw error
//        }
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

        do {
            let manager = SecureEnclaveKeyManager()
            let tag = try manager.createKeypair()
            let publicKey = try manager.publicKey(tag: tag)

            Task {
                let result = try await sendCreateSubOrgRequest(
                    ephemeralPublicKey: publicKey.base64EncodedString(),
                    passkeyRegistrationResult: result,
                    displayName: displayName
                )

                guard let client, let result else {
                    throw TurnkeyAuthServiceError.failedCreatingSubOrganization
                }

                let sessionResponse = try await client.createReadWriteSession(
                    organizationId: Secrets.TURNKEY_PUBLIC_ORGANIZATION_ID,
                    targetPublicKey: publicKey.base64EncodedString(),
                    userId: nil,
                    apiKeyName: nil,
                    expirationSeconds: "86400" // 24 hours
                )

                let whoamiResponse = try await client.getWhoami(
                    organizationId: Secrets.TURNKEY_PUBLIC_ORGANIZATION_ID)

                Logger.info("Turnkey Whoami: \(whoamiResponse)")
                let whoami = try whoamiResponse.ok.body.json

                Logger.info("Finished registering with Turnkey: \(result)")
            }
        } catch {
            Logger.error("Error registering with Turnkey: \(error)")
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

    // MARK: - TurnKey
    func sendCreateSubOrgRequest(
        ephemeralPublicKey: String,
        passkeyRegistrationResult: PasskeyRegistrationResult,
        displayName: String
    ) async throws -> CreateSubOrganizationResponse? {
        guard let client = client else {
            throw TurnkeyAuthServiceError.uninitializedTurnkeyClient
        }

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
