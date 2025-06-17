import Combine
import Foundation
import GRDB

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

    static func testClient(
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
        let databaseManager = MockDatabaseManager.previews
        let messagingService = MockMessagingService()
        return .init(authService: authService,
                     messagingService: messagingService,
                     databaseManager: databaseManager)
    }

    internal init(authService: any AuthServiceProtocol,
                  messagingService: any MessagingServiceProtocol,
                  databaseManager: any DatabaseManagerProtocol) {
        self.authService = authService
        self.messagingService = messagingService
        self.databaseManager = databaseManager
    }

    var authState: AnyPublisher<AuthServiceState, Never> {
        authService.authStatePublisher.eraseToAnyPublisher()
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
        await messagingService.stop()
    }

    var messaging: any MessagingServiceProtocol {
        messagingService
    }
}
