import AuthenticationServices
import CryptoKit
import Foundation

public struct PasskeyResponse {
    public struct Attestation {
        let credentialId: String
        let clientDataJson: String
        let attestationObject: String
    }

    let challenge: String
    let attestation: Attestation
}

public actor PasskeyAuth {
    struct ClientDataJSON: Codable {
        let challenge: String
    }

    private var isAuthenticating: Bool = false
    /// The presentation context provider for the passkey authentication
    private var presentationContextProvider: PasskeyPresentationContextProvider?

    // Rate limiting
    private var lastRequestTime: Date?
    private let minimumRequestInterval: TimeInterval = 1.0 // Minimum 1 second between requests
    private let rpID: String

    /// Creates a new PasskeyAuth instance
    /// - Parameter configuration: The configuration for the passkey authentication
    public init(rpID: String) {
        guard !rpID.isEmpty else {
            fatalError("RP ID cannot be empty")
        }
        self.rpID = rpID
    }

    /// Sets the presentation context provider for the passkey authentication
    /// - Parameter provider: The provider that will handle presenting the authentication UI
    public func setPresentationContextProvider(_ provider: PasskeyPresentationContextProvider) {
        self.presentationContextProvider = provider
    }

    /// Registers a new passkey
    /// - Parameter displayName: The display name for the passkey
    /// - Returns: A PasskeyResponse containing the registration result
    /// - Throws: Various PasskeyError cases if registration fails
    public func registerPasskey(displayName: String) async throws -> PasskeyResponse {
        guard let presentationContextProvider = presentationContextProvider else {
            throw PasskeyError.configurationError("Presentation context provider not set")
        }

        guard !isAuthenticating else {
            throw PasskeyError.authenticationInProgress
        }

        let challengeData = generateRandomBuffer()

        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: rpID
        )

        let userID = Data(UUID().uuidString.utf8)

        let request = provider.createCredentialRegistrationRequest(
            challenge: challengeData,
            name: displayName,
            userID: userID
        )
        request.userVerificationPreference = .required

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.presentationContextProvider = presentationContextProvider
        let asyncController = AsyncAuthorizationController(controller: controller)

        setAuthenticating(true)

        do {
            let authResponse = try await asyncController.performRequests()
            switch authResponse {
            case .registration(let registration):
                guard let rawAttestationObject = registration.rawAttestationObject else {
                    throw PasskeyError.registrationFailed("Missing attestation object")
                }
                let clientDataJSON = try JSONDecoder().decode(ClientDataJSON.self,
                                                              from: registration.rawClientDataJSON)
                let challenge = clientDataJSON.challenge
                let attestationObject = rawAttestationObject.base64URLEncodedString()
                let clientDataJson = registration.rawClientDataJSON.base64URLEncodedString()
                let credentialId = registration.credentialID.base64URLEncodedString()

                return .init(challenge: challenge,
                             attestation: .init(
                                credentialId: credentialId,
                                clientDataJson: clientDataJson,
                                attestationObject: attestationObject
                             ))
            case .assertion:
                throw PasskeyError.registrationFailed("Unexpected assertion response")
            }
        } catch {
            throw PasskeyError.registrationFailed("Registration failed")
        }
    }

    /// Logs in with a passkey
    /// - Returns: A PasskeyResponse containing the login result
    /// - Throws: Various PasskeyError cases if login fails
    public func loginWithPasskey() async throws -> PasskeyResponse {
        guard let presentationContextProvider = presentationContextProvider else {
            throw PasskeyError.configurationError("Presentation context provider not set")
        }

        guard !isAuthenticating else {
            throw PasskeyError.authenticationInProgress
        }

        let challengeData = generateRandomBuffer()

        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: rpID
        )

        let request = provider.createCredentialAssertionRequest(challenge: challengeData)
        request.userVerificationPreference = .required

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.presentationContextProvider = presentationContextProvider
        let asyncController = AsyncAuthorizationController(controller: controller)

        setAuthenticating(true)

        do {
            let authResponse = try await asyncController.performRequests()
            switch authResponse {
            case .assertion:
                return .init(challenge: challengeData.base64EncodedString(),
                             attestation: .init(credentialId: "",
                                                clientDataJson: "",
                                                attestationObject: ""))
            case .registration:
                throw PasskeyError.authenticationFailed("Unexpected registration response")
            }
        } catch {
            throw PasskeyError.authenticationFailed("Login failed")
        }
    }

    // MARK: - Private Methods

    private func generateRandomBuffer() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    fileprivate func setAuthenticating(_ value: Bool) {
        isAuthenticating = value
    }
}
