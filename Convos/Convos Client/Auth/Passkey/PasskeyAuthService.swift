import Combine
import Foundation
import PasskeyAuth
import XMTPiOS

class PasskeyAuthService: AuthServiceProtocol {
    var state: AuthServiceState {
        authStateSubject.value
    }

    var authStatePublisher: AnyPublisher<AuthServiceState, Never> {
        return authStateSubject.eraseToAnyPublisher()
    }

    var accountsService: (any AuthAccountsServiceProtocol)? {
        nil
    }

    private let environment: AppEnvironment
    private var authStateSubject: CurrentValueSubject<AuthServiceState, Never> = .init(.unknown)
    private let passkeyAuth: PasskeyAuth
    private let passkeyIdentityStore: PasskeyIdentityStore = .init()

    init(environment: AppEnvironment) {
        guard let passkeyBaseURL = URL(string: Secrets.PASSKEY_API_BASE_URL) else {
            fatalError("Failed constructing base URL")
        }

        self.environment = environment

        do {
            let config = try PasskeyConfiguration(
                baseURL: passkeyBaseURL,
                rpID: environment.relyingPartyIdentifier
            )
            passkeyAuth = PasskeyAuth(configuration: config)
        } catch {
            fatalError(error.localizedDescription)
        }

        do {
            try refreshAuthState()
        } catch {
            Logger.error("Error refreshing auth state: \(error)")
        }
    }

    func prepare() async throws {
        Task { @MainActor in
            let presentationProvider = PasskeyPresentationProvider()
            await passkeyAuth.setPresentationContextProvider(presentationProvider)
        }
    }

    func signIn() async throws {
        let (assertion, response) = try await passkeyAuth.loginWithPasskey()
        let identity = try passkeyIdentityStore.save(
            credentialID: assertion.credentialID,
            publicKey: response.publicKey,
            userID: response.userID
        )
        let signingKey = PasskeySigningKey(credentialID: identity.credentialID,
                                           publicKey: identity.publicKey,
                                           passkeyAuth: passkeyAuth)
        authStateSubject.send(
            .authorized(
                AuthServiceResult(
                    inboxes: [
                        AuthServiceInbox(
                            type: .standard,
                            provider: .external(.passkey),
                            providerId: response.userID,
                            signingKey: signingKey,
                            databaseKey: identity.databaseKey
                        )
                    ]
                )
            )
        )
    }

    func register(displayName: String) async throws {
        let (assertion, response) = try await passkeyAuth.registerPasskey(displayName: displayName)
        let identity = try passkeyIdentityStore.save(
            credentialID: assertion.credentialID,
            publicKey: response.publicKey,
            userID: response.userID
        )
        let signingKey = PasskeySigningKey(credentialID: identity.credentialID,
                                           publicKey: identity.publicKey,
                                           passkeyAuth: passkeyAuth)
        authStateSubject.send(
            .registered(
                AuthServiceRegisteredResult(
                    displayName: displayName,
                    inbox: AuthServiceInbox(
                        type: .standard,
                        provider: .external(.passkey),
                        providerId: response.userID,
                        signingKey: signingKey,
                        databaseKey: identity.databaseKey
                    )
                )
            )
        )
    }

    func signOut() async throws {
        try passkeyIdentityStore.delete()
        authStateSubject.send(.unauthorized)
    }

    // MARK: - Private

    private func refreshAuthState() throws {
        if let identity = try passkeyIdentityStore.load() {
            let signingKey = PasskeySigningKey(credentialID: identity.credentialID,
                                               publicKey: identity.publicKey,
                                               passkeyAuth: passkeyAuth)
            let result = AuthServiceResult(
                inboxes: [
                    AuthServiceInbox(
                        type: .standard,
                        provider: .external(.passkey),
                        providerId: identity.userID,
                        signingKey: signingKey,
                        databaseKey: identity.databaseKey
                    )
                ]
            )
            authStateSubject.send(.authorized(result))
        } else {
            authStateSubject.send(.unauthorized)
        }
    }
}
