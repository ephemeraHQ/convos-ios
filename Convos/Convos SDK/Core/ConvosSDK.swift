import Combine
import Foundation

public enum ConvosSDK {
    public final class Convos {
        private let authService: AuthServiceProtocol
        private let messagingService: any MessagingServiceProtocol

        public static let shared: Convos = .init(authService: TurnkeyAuthService())
        public static let mock: Convos = .init(authService: PasskeyAuthService())

        private init(authService: AuthServiceProtocol) {
            self.authService = authService
            self.messagingService = MessagingService(authService: authService)
        }

        public var authState: AnyPublisher<AuthServiceState, Never> {
            authService.authStatePublisher().eraseToAnyPublisher()
        }

        public func prepare() async throws {
            try await authService.prepare()
        }

        public func signIn() async throws {
            try await authService.signIn()
        }

        public func register(displayName: String) async throws {
            try await authService.register(displayName: displayName)
        }

        public func signOut() async throws {
            try await authService.signOut()
        }

        public var messaging: any MessagingServiceProtocol {
            messagingService
        }
    }
}
