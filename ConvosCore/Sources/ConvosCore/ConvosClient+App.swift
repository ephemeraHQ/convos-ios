import Foundation

// App specific methods not needed in our tests target
extension ConvosClient {
    public static func client(environment: AppEnvironment) -> ConvosClient {
        let databaseManager = DatabaseManager(environment: environment)
        let localAuthService = SecureEnclaveAuthService(accessGroup: environment.keychainAccessGroup)
        let databaseWriter = databaseManager.dbWriter
        let databaseReader = databaseManager.dbReader
        let sessionManager = SessionManager(
            authService: localAuthService,
            databaseWriter: databaseWriter,
            databaseReader: databaseReader,
            environment: environment
        )
        return .init(authService: localAuthService,
                     sessionManager: sessionManager,
                     databaseManager: databaseManager,
                     environment: environment)
    }
}
