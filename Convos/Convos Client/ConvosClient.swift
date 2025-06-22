import Combine
import Foundation
import GRDB

final class ConvosClient {
    private let authService: AuthServiceProtocol
    private let sessionManager: any SessionManagerProtocol
    private let databaseManager: any DatabaseManagerProtocol

    var databaseWriter: any DatabaseWriter {
        databaseManager.dbWriter
    }

    var databaseReader: any DatabaseReader {
        databaseManager.dbReader
    }

    var session: any SessionManagerProtocol {
        sessionManager
    }

    static func testClient(
        authService: AuthServiceProtocol = MockAuthService()
    ) -> ConvosClient {
        let databaseManager = MockDatabaseManager.shared
        let sessionManager = MockInboxesService()
        return .init(authService: authService,
                     sessionManager: sessionManager,
                     databaseManager: databaseManager)
    }

    static func mock() -> ConvosClient {
        let authService = MockAuthService()
        let databaseManager = MockDatabaseManager.previews
        let sessionManager = MockInboxesService()
        return .init(authService: authService,
                     sessionManager: sessionManager,
                     databaseManager: databaseManager)
    }

    internal init(authService: any AuthServiceProtocol,
                  sessionManager: any SessionManagerProtocol,
                  databaseManager: any DatabaseManagerProtocol) {
        self.authService = authService
        self.sessionManager = sessionManager
        self.databaseManager = databaseManager
    }

    var authState: AnyPublisher<AuthServiceState, Never> {
        authService.authStatePublisher.eraseToAnyPublisher()
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
//        await messagingService.stop()
    }
}
