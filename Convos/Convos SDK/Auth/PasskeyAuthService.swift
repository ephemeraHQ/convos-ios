// swiftlint:disable force_try force_unwrapping

import Combine
import Foundation

class PasskeyAuthService: ConvosSDK.AuthServiceProtocol {
    struct PasskeyAuthResult: ConvosSDK.AuthorizedResultType {
        let privateKeyData: Data
    }

    enum PasskeyAuthServiceError: Error {
        case invalidBaseURL
    }

    var state: ConvosSDK.AuthServiceState {
        authStateSubject.value
    }

    private var authStateSubject: CurrentValueSubject<ConvosSDK.AuthServiceState, Never> = .init(.unknown)

    let passkeyHelper: PasskeyAuthHelper

    init() {
        let passkeyBaseURL = URL(string: Secrets.PASSKEY_API_BASE_URL)!
        passkeyHelper = try! PasskeyAuthHelper(baseURL: passkeyBaseURL,
                                               rpID: Secrets.API_RP_ID)
        do {
            try refreshAuthState()
        } catch {
            Logger.error("Error refreshing auth state: \(error)")
        }
    }

    func prepare() async throws {
        Task { @MainActor in
            await passkeyHelper.setupPasskeyPresentationProvider()
        }
    }

    func signIn() async throws {
        let privateKey = try await passkeyHelper.loginWithPasskey()
        authStateSubject.send(.authorized(PasskeyAuthResult(privateKeyData: privateKey)))
    }

    func register(displayName: String) async throws {
        let privateKey = try await passkeyHelper.registerPasskey(displayName: displayName)
        authStateSubject.send(.authorized(PasskeyAuthResult(privateKeyData: privateKey)))
    }

    func signOut() async throws {
        passkeyHelper.logout()
        authStateSubject.send(.unauthorized)
    }

    func authStatePublisher() -> AnyPublisher<ConvosSDK.AuthServiceState, Never> {
        return authStateSubject.eraseToAnyPublisher()
    }

    // MARK: - Private

    private func refreshAuthState() throws {
        if let privateKey = try passkeyHelper.activePrivateKey() {
            authStateSubject.send(.authorized(PasskeyAuthResult(privateKeyData: privateKey)))
        } else {
            authStateSubject.send(.unauthorized)
        }
    }
}

// swiftlint:enable force_try force_unwrapping
