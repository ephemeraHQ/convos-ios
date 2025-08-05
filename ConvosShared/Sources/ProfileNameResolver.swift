import Foundation

public class ProfileNameResolver {
    private let cache: NSCache<NSString, NSString> = NSCache<NSString, NSString>()
    private let appGroupIdentifier: String

    public init(appGroupIdentifier: String) {
        self.appGroupIdentifier = appGroupIdentifier
        // Load persisted cache from UserDefaults
        loadPersistedCache()
    }

    private var appGroupDefaults: UserDefaults? {
        return UserDefaults(suiteName: appGroupIdentifier)
    }

    // MARK: - Public API

    public func resolveProfileName(for inboxId: String) async -> String? {
        // Check memory cache first
        if let cachedName = cache.object(forKey: inboxId as NSString) {
            return cachedName as String
        }

        // Check persisted cache
        if let persistedName = getPersistedName(for: inboxId) {
            // Update memory cache
            cache.setObject(persistedName as NSString, forKey: inboxId as NSString)
            return persistedName
        }

        // Profile fetching from backend API should be implemented by the main app
        // Return nil for now to allow the main app to handle the fetching logic
        return nil
    }

    public func cacheProfileName(_ name: String, for inboxId: String) {
        // Update memory cache
        cache.setObject(name as NSString, forKey: inboxId as NSString)

        // Persist to UserDefaults
        persistName(name, for: inboxId)
    }

    // MARK: - Private Persistence

    private func loadPersistedCache() {
        guard let cachedProfiles = appGroupDefaults?.dictionary(forKey: NotificationConstants.StorageKeys.userProfiles) else {
            return
        }

        for (key, value) in cachedProfiles {
            if let name = value as? String {
                cache.setObject(name as NSString, forKey: key as NSString)
            }
        }
    }

    private func getPersistedName(for inboxId: String) -> String? {
        let profiles = appGroupDefaults?.dictionary(forKey: NotificationConstants.StorageKeys.userProfiles) ?? [:]
        return profiles[inboxId] as? String
    }

    private func persistName(_ name: String, for inboxId: String) {
        var profiles = appGroupDefaults?.dictionary(forKey: NotificationConstants.StorageKeys.userProfiles) ?? [:]
        profiles[inboxId] = name
        appGroupDefaults?.set(profiles, forKey: NotificationConstants.StorageKeys.userProfiles)
    }

    // MARK: - Cleanup

    public func clearCache() {
        cache.removeAllObjects()
        appGroupDefaults?.removeObject(forKey: NotificationConstants.StorageKeys.userProfiles)
    }
}
