import Foundation

enum NotificationExtensionEnvironmentError: Error {
    case failedRetrievingSecureConfiguration
}

/// Helper for notification extensions to get the correct environment configuration
public struct NotificationExtensionEnvironment {
    /// Gets the environment configuration stored by the main app
    /// The NSE expects the main app to have stored its configuration in the shared keychain
    static func getEnvironment() throws -> AppEnvironment {
        // Retrieve the configuration stored by the main app
        guard let storedEnvironment = AppEnvironment.retrieveSecureConfigurationForNotificationExtension() else {
            Logger.warning("⚠️ No stored environment configuration found - main app should store config before NSE runs")
            throw NotificationExtensionEnvironmentError.failedRetrievingSecureConfiguration
        }

        Logger.info("Notification extension using stored environment: \(storedEnvironment.name)")
        return storedEnvironment
    }

    /// Creates a cached push notification handler with the correct environment
    public static func createPushNotificationHandler() throws -> CachedPushNotificationHandler {
        let environment = try getEnvironment()
        let databaseManager = DatabaseManager(environment: environment)
        return CachedPushNotificationHandler(
            authService: SecureEnclaveAuthService(accessGroup: environment.keychainAccessGroup),
            databaseReader: databaseManager.dbReader,
            databaseWriter: databaseManager.dbWriter,
            environment: environment,
            isNotificationServiceExtension: true
        )
    }
}
