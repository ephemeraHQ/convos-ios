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
            Logger.info("Scene launched with Universal Link: \(url)")
            // Post notification after a small delay to ensure app is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.post(
                    name: .deepLinkReceived,
                    object: nil,
                    userInfo: ["url": url]
                )
            }
        }

        // Handle custom URL schemes on cold launch
        if let urlContext = connectionOptions.urlContexts.first {
            Logger.info("Scene launched with custom URL: \(urlContext.url)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.post(
                    name: .deepLinkReceived,
                    object: nil,
                    userInfo: ["url": urlContext.url]
                )
            }
        }
    }

    // Handle custom URL schemes when app is already running
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        Logger.info("Scene received custom URL: \(url)")
        NotificationCenter.default.post(
            name: .deepLinkReceived,
            object: nil,
            userInfo: ["url": url]
        )
    }

    // Handle Universal Links when app is already running
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else {
            return
        }
        Logger.info("Scene received Universal Link: \(url)")
        NotificationCenter.default.post(
            name: .deepLinkReceived,
            object: nil,
            userInfo: ["url": url]
        )
    }
}
