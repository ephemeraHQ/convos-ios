import Combine
import Foundation
import GRDB

final class ConvosClient {
    private let authService: AuthServiceProtocol
    private let localAuthService: LocalAuthServiceProtocol
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
        authService: AuthServiceProtocol = MockAuthService(),
        localAuthService: LocalAuthServiceProtocol = SecureEnclaveAuthService()
    ) -> ConvosClient {
        let databaseManager = MockDatabaseManager.shared
        let sessionManager = MockInboxesService()
        return .init(authService: authService,
                     localAuthService: localAuthService,
                     sessionManager: sessionManager,
                     databaseManager: databaseManager)
    }

    static func mock() -> ConvosClient {
        let authService = MockAuthService()
        let databaseManager = MockDatabaseManager.previews
        let sessionManager = MockInboxesService()
        let localAuthService = SecureEnclaveAuthService()
        return .init(authService: authService,
                     localAuthService: localAuthService,
                     sessionManager: sessionManager,
                     databaseManager: databaseManager)
    }

    internal init(authService: any AuthServiceProtocol,
                  localAuthService: any LocalAuthServiceProtocol,
                  sessionManager: any SessionManagerProtocol,
                  databaseManager: any DatabaseManagerProtocol) {
        self.authService = authService
        self.localAuthService = localAuthService
        self.sessionManager = sessionManager
        self.databaseManager = databaseManager
    }

    var authState: AnyPublisher<AuthServiceState, Never> {
        sessionManager.authState
    }

    var externalAuthState: AnyPublisher<AuthServiceState, Never> {
        authService.authStatePublisher.eraseToAnyPublisher()
    }

    var localAuthState: AnyPublisher<AuthServiceState, Never> {
        localAuthService.authStatePublisher.eraseToAnyPublisher()
    }

    func prepare() async throws {
        try await sessionManager.prepare()
    }

    func signIn() async throws {
        try await authService.signIn()
    }

    func getStarted() throws {
        let _ = try localAuthService.register(displayName: "User", inboxType: .standard)
    }

    func register(displayName: String) async throws {
        try await authService.register(displayName: displayName)
    }

    func signOut() async throws {
        try localAuthService.deleteAll()
        try await authService.signOut()
//        await messagingService.stop()
    }
}
