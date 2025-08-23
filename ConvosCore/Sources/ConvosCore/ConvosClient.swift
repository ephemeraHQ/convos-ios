import Combine
import Foundation
import GRDB

public final class ConvosClient {
    private let sessionManager: any SessionManagerProtocol
    private let databaseManager: any DatabaseManagerProtocol
    private let environment: AppEnvironment

    var databaseWriter: any DatabaseWriter {
        databaseManager.dbWriter
    }

    var databaseReader: any DatabaseReader {
        databaseManager.dbReader
    }

    public var session: any SessionManagerProtocol {
        sessionManager
    }

    public static func testClient() -> ConvosClient {
        let databaseManager = MockDatabaseManager.shared
        let sessionManager = SessionManager(
            databaseWriter: databaseManager.dbWriter,
            databaseReader: databaseManager.dbReader,
            environment: .tests
        )
        return .init(sessionManager: sessionManager,
                     databaseManager: databaseManager,
                     environment: .tests)
    }

    public static func mock() -> ConvosClient {
        let databaseManager = MockDatabaseManager.previews
        let sessionManager = MockInboxesService()
        return .init(sessionManager: sessionManager,
                     databaseManager: databaseManager,
                     environment: .tests)
    }

    internal init(sessionManager: any SessionManagerProtocol,
                  databaseManager: any DatabaseManagerProtocol,
                  environment: AppEnvironment) {
        self.sessionManager = sessionManager
        self.databaseManager = databaseManager
        self.environment = environment
    }
}
