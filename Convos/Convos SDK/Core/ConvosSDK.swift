import Combine
import Foundation
import GRDB

public enum ConvosSDK {
    public final class Convos {
        private let authService: AuthServiceProtocol
        private let messagingService: any MessagingServiceProtocol

        public var databaseWriter: any DatabaseWriter {
            DatabaseManager.shared.dbPool as (any DatabaseWriter)
        }

        public var databaseReader: any DatabaseReader {
            DatabaseManager.shared.dbPool as (any DatabaseReader)
        }

        static func sdk(authService: AuthServiceProtocol) -> Convos {
            let databaseWriter = DatabaseManager.shared.dbPool
            let userWriter = DBUserWriter(databaseWriter: databaseWriter)
            let messagingService = MessagingService(authService: authService,
                                                    userWriter: userWriter)
            return .init(authService: authService,
                         messagingService: messagingService)
        }

        private init(authService: AuthServiceProtocol,
                     messagingService: MessagingServiceProtocol) {
            self.authService = authService
            self.messagingService = messagingService
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
