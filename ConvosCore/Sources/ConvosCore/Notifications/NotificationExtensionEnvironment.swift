import Foundation

enum NotificationExtensionEnvironmentError: Error {
    case failedRetrievingSecureConfiguration
}

/// Helper for notification extensions to get the correct environment configuration
public struct NotificationExtensionEnvironment {
    // Cache the environment after first successful retrieval
    private static var cachedEnvironment: AppEnvironment?

    /// Gets the environment configuration stored by the main app
    /// The NSE expects the main app to have stored its configuration in the shared keychain
    /// The environment is cached after first successful retrieval for performance
    public static func getEnvironment() throws -> AppEnvironment {
        // Return cached environment if available
        if let cached = cachedEnvironment {
            return cached
        }

        // Retrieve the configuration stored by the main app
        guard let storedEnvironment = AppEnvironment.retrieveSecureConfigurationForNotificationExtension() else {
            Logger.warning("No stored environment configuration found - main app should store config before NSE runs")
            throw NotificationExtensionEnvironmentError.failedRetrievingSecureConfiguration
        }

        // Cache for future use
        cachedEnvironment = storedEnvironment

        Logger.info("Environment configuration loaded and cached: \(storedEnvironment.name)")
        return storedEnvironment
    }

    /// Creates a cached push notification handler with the correct environment
    /// This should typically be called once and stored as a global singleton
    public static func createPushNotificationHandler() throws -> CachedPushNotificationHandler {
        let environment = try getEnvironment()
        let databaseManager = DatabaseManager(environment: environment)

        Logger.info("Creating CachedPushNotificationHandler with environment: \(environment.name)")

        CachedPushNotificationHandler.initialize(
            databaseReader: databaseManager.dbReader,
            databaseWriter: databaseManager.dbWriter,
            environment: environment
        )
        return CachedPushNotificationHandler.shared
    }
}
