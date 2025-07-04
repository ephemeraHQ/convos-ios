import Foundation

// App specific methods not needed in our tests target
extension ConvosClient {
    static func client(databaseManager: any DatabaseManagerProtocol = DatabaseManager.shared,
                       environment: AppEnvironment) -> ConvosClient {
        let authService = TurnkeyAuthService(environment: environment)
        let localAuthService = SecureEnclaveAuthService()
        let databaseWriter = databaseManager.dbWriter
        let databaseReader = databaseManager.dbReader
        let sessionManager = SessionManager(
            authService: authService,
            localAuthService: localAuthService,
            databaseWriter: databaseWriter,
            databaseReader: databaseReader,
            environment: environment
        )
        return .init(authService: authService,
                     localAuthService: localAuthService,
                     sessionManager: sessionManager,
                     databaseManager: databaseManager)
    }
}
