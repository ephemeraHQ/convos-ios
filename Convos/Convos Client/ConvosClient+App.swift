import Foundation

// App specific methods not needed in our tests target
extension ConvosClient {
    static func client(databaseManager: any DatabaseManagerProtocol = DatabaseManager.shared,
                       environment: AppEnvironment) -> ConvosClient {
        let authService = TurnkeyAuthService(environment: environment)
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
}
