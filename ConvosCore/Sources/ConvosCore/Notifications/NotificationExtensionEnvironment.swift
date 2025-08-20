import Foundation

/// Helper for notification extensions to get the correct environment configuration
public struct NotificationExtensionEnvironment {
    /// Gets the environment configuration stored by the main app
    /// The NSE expects the main app to have stored its configuration in the shared keychain
    public static func getEnvironment() -> AppEnvironment {
        // Detect the environment to determine the correct access group
        let detectedEnvironment = AppEnvironment.detected()

        // Retrieve the configuration stored by the main app
        guard let storedEnvironment = AppEnvironment.retrieveSecureConfiguration(accessGroup: detectedEnvironment.appGroupIdentifier) else {
            Logger.warning("⚠️ No stored environment configuration found - main app should store config before NSE runs")
            Logger.info("Notification extension using detected environment: \(detectedEnvironment.name)")
            return detectedEnvironment
        }

        Logger.info("Notification extension using stored environment: \(storedEnvironment.name)")
        return storedEnvironment
    }

    /// Creates an auth service with the correct environment for the notification extension
    public static func createAuthService() -> SecureEnclaveAuthService {
        let environment = getEnvironment()
        // Use the keychain group identifier as the keychain access group (with team prefix added by system)
        return SecureEnclaveAuthService(accessGroup: environment.keychainAccessGroup)
    }

    /// Creates a cached push notification handler with the correct environment
    public static func createPushNotificationHandler() -> CachedPushNotificationHandler {
        let environment = getEnvironment()
        let databaseManager = DatabaseManager.shared

        return CachedPushNotificationHandler(
            authService: createAuthService(),
            databaseReader: databaseManager.dbReader,
            databaseWriter: databaseManager.dbWriter,
            environment: environment,
            isNotificationServiceExtension: true
        )
    }
}
