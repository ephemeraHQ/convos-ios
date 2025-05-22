import Combine
import Foundation
import GRDB

enum ConvosSDK {
    final class ConvosClient {
        private let authService: AuthServiceProtocol
        private let messagingService: any MessagingServiceProtocol

        var databaseWriter: any DatabaseWriter {
            DatabaseManager.shared.dbWriter
        }

        var databaseReader: any DatabaseReader {
            DatabaseManager.shared.dbReader
        }

        static func sdk(authService: AuthServiceProtocol) -> ConvosClient {
            let databaseWriter = DatabaseManager.shared.dbWriter
            let databaseReader = DatabaseManager.shared.dbReader
            let messagingService = MessagingService(authService: authService,
                                                    databaseWriter: databaseWriter,
                                                    databaseReader: databaseReader)
            return .init(authService: authService,
                         messagingService: messagingService)
        }

        private init(authService: AuthServiceProtocol,
                     messagingService: MessagingServiceProtocol) {
            self.authService = authService
            self.messagingService = messagingService
        }

        var authState: AnyPublisher<AuthServiceState, Never> {
            authService.authStatePublisher().eraseToAnyPublisher()
        }

        var supportsMultipleAccounts: Bool {
            authService.supportsMultipleAccounts
        }

        func prepare() async throws {
            try await authService.prepare()
        }

        func signIn() async throws {
            try await authService.signIn()
        }

        func register(displayName: String) async throws {
            try await authService.register(displayName: displayName)
        }

        func signOut() async throws {
            try await authService.signOut()
        }

        var messaging: any MessagingServiceProtocol {
            messagingService
        }
    }
}
