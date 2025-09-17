import ConvosCore
import SwiftUI
import UIKit

class ConvosSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Handle Universal Links on cold launch (e.g., from Camera app)
        if let userActivity = connectionOptions.userActivities.first,
           userActivity.activityType == NSUserActivityTypeBrowsingWeb,
           let url = userActivity.webpageURL {
            handleURL(url, context: "Scene launched")
        }
        // Handle custom URL schemes on cold launch (only if no Universal Link was processed)
        else if let urlContext = connectionOptions.urlContexts.first {
            handleURL(urlContext.url, context: "Scene launched")
        }
    }

    // Handle custom URL schemes when app is already running
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        handleURL(url, context: "Scene received custom URL")
    }

    // Handle Universal Links when app is already running
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else {
            return
        }
        handleURL(url, context: "Scene received Universal Link")
    }

    // Centralized URL handling with security validation
    private func handleURL(_ url: URL, context: String) {
        // Validate URL before processing
        guard DeepLinkHandler.destination(for: url) != nil else {
            Logger.warning("\(context) - Invalid deep link ignored: [scheme: \(url.scheme ?? "unknown"), host: \(url.host ?? "unknown")]")
            return
        }

        Logger.info("\(context) - Valid deep link: [scheme: \(url.scheme ?? "unknown"), host: \(url.host ?? "unknown")]")

        if context.contains("launched") {
            // For cold launch, store URL and let SwiftUI app handle when ready
            // This path is critical for Camera app Universal Links
            SceneURLStorage.shared.storePendingURL(url)
        } else {
            // App is already running, process immediately
            NotificationCenter.default.post(
                name: .deepLinkReceived,
                object: nil,
                userInfo: ["url": url]
            )
        }
    }
}
