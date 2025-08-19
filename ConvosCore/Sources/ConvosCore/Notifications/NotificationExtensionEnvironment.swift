import Foundation

/// Helper for notification extensions to get the correct environment configuration
public struct NotificationExtensionEnvironment {
    /// Gets the appropriate environment for the notification extension
    /// This will try to retrieve the configuration stored by the main app,
    /// or fall back to auto-detection based on bundle identifier and app groups
    public static func getEnvironment() -> AppEnvironment {
        // First, try to get the configuration stored securely by the main app
        if let storedEnvironment = AppEnvironment.retrieveSecureConfigurationWithFallback() {
            Logger.info("Notification extension using stored environment: \(storedEnvironment.name)")
            return storedEnvironment
        }

        // Fall back to auto-detection
        let detectedEnvironment = AppEnvironment.detected()
        Logger.info("Notification extension using detected environment: \(detectedEnvironment.name)")
        return detectedEnvironment
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
            environment: environment
        )
    }
}
