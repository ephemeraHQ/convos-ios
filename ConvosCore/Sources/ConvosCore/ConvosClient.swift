import Combine
import Foundation
import GRDB

final class ConvosClient {
    private let authService: any LocalAuthServiceProtocol
    private let sessionManager: any SessionManagerProtocol
    private let databaseManager: any DatabaseManagerProtocol
    private let environment: AppEnvironment

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
        authService: any LocalAuthServiceProtocol = SecureEnclaveAuthService()
    ) -> ConvosClient {
        let databaseManager = MockDatabaseManager.shared
        let sessionManager = SessionManager(
            authService: authService,
            databaseWriter: databaseManager.dbWriter,
            databaseReader: databaseManager.dbReader,
            environment: .tests
        )
        return .init(authService: authService,
                     sessionManager: sessionManager,
                     databaseManager: databaseManager,
                     environment: .tests)
    }

    static func mock() -> ConvosClient {
        let authService = MockAuthService()
        let databaseManager = MockDatabaseManager.previews
        let sessionManager = MockInboxesService()
        return .init(authService: authService,
                     sessionManager: sessionManager,
                     databaseManager: databaseManager,
                     environment: .tests)
    }

    internal init(authService: any LocalAuthServiceProtocol,
                  sessionManager: any SessionManagerProtocol,
                  databaseManager: any DatabaseManagerProtocol,
                  environment: AppEnvironment) {
        self.authService = authService
        self.sessionManager = sessionManager
        self.databaseManager = databaseManager
        self.environment = environment
    }

    var authState: AnyPublisher<AuthServiceState, Never> {
        sessionManager.authState
    }

    func prepare() throws {
        try sessionManager.prepare()
    }
}
