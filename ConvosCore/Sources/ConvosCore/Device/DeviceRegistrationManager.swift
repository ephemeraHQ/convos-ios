import Foundation

/// App-level manager for device registration with the backend.
///
/// Device registration is a device-level concern (not inbox-specific).
/// It uses Firebase AppCheck for authentication, not JWT tokens (which are inbox-specific).
///
/// This allows device registration to happen immediately on app launch,
/// without waiting for any inbox to be authorized.
///
/// The manager persists registration state in UserDefaults to avoid unnecessary re-registrations
/// across app launches and to detect when push tokens change.
public final class DeviceRegistrationManager {
    // MARK: - Properties

    private let apiClient: any ConvosAPIBaseProtocol

    public init(environment: AppEnvironment) {
        self.apiClient = ConvosAPIClientFactory.client(environment: environment)
    }

    // For testing
    internal init(apiClient: any ConvosAPIBaseProtocol) {
        self.apiClient = apiClient
    }

    // MARK: - Public API

    /// Registers the device with the backend if needed (first time or token changed).
    /// Can be called multiple times safely - will skip if already registered with same token.
    ///
    /// Uses Firebase AppCheck for authentication (device-level, not inbox-specific).
    /// This can be called immediately on app launch, without waiting for inbox authorization.
    ///
    /// Retry strategy: Will retry on every call if previous attempt failed (UserDefaults not updated on failure).
    /// This ensures eventual consistency even with intermittent network issues.
    public func registerDeviceIfNeeded() async {
        let deviceId = DeviceInfo.deviceIdentifier
        let pushToken = PushNotificationRegistrar.token

        // Get last registered token from UserDefaults (persisted across app launches)
        let lastTokenKey = "lastRegisteredDevicePushToken_\(deviceId)"
        let hasRegisteredKey = "hasRegisteredDevice_\(deviceId)"
        let lastSuccessKey = "lastSuccessfulRegistration_\(deviceId)"

        let lastToken = UserDefaults.standard.string(forKey: lastTokenKey)
        let hasEverRegistered = UserDefaults.standard.bool(forKey: hasRegisteredKey)
        let lastSuccessTimestamp = UserDefaults.standard.double(forKey: lastSuccessKey)

        let now = Date().timeIntervalSince1970
        let daysSinceLastSuccess = (now - lastSuccessTimestamp) / (24 * 60 * 60)

        // Register if:
        // 1. Never registered this device before (important for v1→v2 migration)
        // 2. Push token has changed (including nil → token and token → nil)
        // 3. It's been more than 7 days since last successful registration (drift check)
        let shouldRegister = !hasEverRegistered ||
                           lastToken != pushToken ||
                           daysSinceLastSuccess > 7

        guard shouldRegister else {
            Logger.info("Device already registered with this token (last success: \(Int(daysSinceLastSuccess)) days ago)")
            return
        }

        let reason = !hasEverRegistered ? "first time" :
                    lastToken != pushToken ? "token changed" :
                    "periodic refresh"

        do {
            Logger.info("Registering device (\(reason), token: \(pushToken != nil ? "present" : "nil"))")

            // Register device using AppCheck (handled by API client)
            try await apiClient.registerDevice(deviceId: deviceId, pushToken: pushToken)

            // Only persist on SUCCESS - ensures retry on failure
            UserDefaults.standard.set(true, forKey: hasRegisteredKey)
            UserDefaults.standard.set(now, forKey: lastSuccessKey)
            if let pushToken = pushToken {
                UserDefaults.standard.set(pushToken, forKey: lastTokenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastTokenKey)
            }

            Logger.info("Successfully registered device")
        } catch {
            Logger.error("Failed to register device: \(error). Will retry on next attempt.")
        }
    }

    /// Clears the device registration state from UserDefaults.
    /// Call this on logout, "Delete all data", or when you want to force re-registration.
    public static func clearRegistrationState() {
        let deviceId = DeviceInfo.deviceIdentifier
        UserDefaults.standard.removeObject(forKey: "lastRegisteredDevicePushToken_\(deviceId)")
        UserDefaults.standard.removeObject(forKey: "hasRegisteredDevice_\(deviceId)")
        UserDefaults.standard.removeObject(forKey: "lastSuccessfulRegistration_\(deviceId)")
        Logger.info("Cleared device registration state")
    }

    /// Returns true if this device has been registered at least once.
    public static func hasRegisteredDevice() -> Bool {
        let deviceId = DeviceInfo.deviceIdentifier
        return UserDefaults.standard.bool(forKey: "hasRegisteredDevice_\(deviceId)")
    }
}
