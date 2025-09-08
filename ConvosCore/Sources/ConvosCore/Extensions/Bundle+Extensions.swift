import Foundation

extension Bundle {
    /// Returns the app's marketing version (CFBundleShortVersionString)
    public static var appVersion: String {
        main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
}
