import Combine
import Foundation
import GRDB

enum ConvosSDK {
    final class ConvosClient {
        private let authService: AuthServiceProtocol
        private let messagingService: any MessagingServiceProtocol
        private let databaseManager: any DatabaseManagerProtocol

        var databaseWriter: any DatabaseWriter {
            databaseManager.dbWriter
        }

        var databaseReader: any DatabaseReader {
            databaseManager.dbReader
        }

        static func testBundle(
            authService: AuthServiceProtocol = MockAuthService()
        ) -> ConvosClient {
            let databaseManager = MockDatabaseManager.shared
            let messagingService = MessagingService(
                authService: authService,
                databaseWriter: databaseManager.dbWriter,
                databaseReader: databaseManager.dbReader,
                apiClient: MockAPIClient(),
                environment: .local
            )
            return .init(authService: authService,
                         messagingService: messagingService,
                         databaseManager: databaseManager)
        }

        static func mock() -> ConvosClient {
            let authService = MockAuthService()
            let databaseManager = MockDatabaseManager.shared
            let messagingService = MockMessagingService()
            return .init(authService: authService,
                         messagingService: messagingService,
                         databaseManager: databaseManager)
        }

        static func sdk(authService: AuthServiceProtocol = SecureEnclaveAuthService(),
                        databaseManager: any DatabaseManagerProtocol = DatabaseManager.shared,
                        environment: MessagingServiceEnvironment) -> ConvosClient {
            let databaseWriter = databaseManager.dbWriter
            let databaseReader = databaseManager.dbReader
            let messagingService = MessagingService(authService: authService,
                                                    databaseWriter: databaseWriter,
                                                    databaseReader: databaseReader,
                                                    apiClient: ConvosAPIClient.shared,
                                                    environment: environment)
            return .init(authService: authService,
                         messagingService: messagingService,
                         databaseManager: databaseManager)
        }

        private init(authService: any AuthServiceProtocol,
                     messagingService: any MessagingServiceProtocol,
                     databaseManager: any DatabaseManagerProtocol) {
            self.authService = authService
            self.messagingService = messagingService
            self.databaseManager = databaseManager
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
