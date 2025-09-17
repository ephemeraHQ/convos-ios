import ConvosCore
import Foundation
import SwiftUI
import UIKit

@MainActor
class ConvosSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        // Get the ConvosClient from AppDelegate
        guard let appDelegate = UIApplication.shared.delegate as? ConvosAppDelegate else { return }
        let environment = ConfigManager.shared.currentEnvironment
        let convos: ConvosClient = .client(environment: environment)
        appDelegate.session = convos.session

        // Create the SwiftUI window
        let window = UIWindow(windowScene: windowScene)
        self.window = window
        window.rootViewController = UIHostingController(rootView: ConversationsView(session: convos.session).withSafeAreaEnvironment())
        window.makeKeyAndVisible()

        // Handle URLs that launched the app (when app was not running)
        if let urlContext = connectionOptions.urlContexts.first {
            handleIncomingURL(urlContext.url)
        }

        // Handle Universal Links that launched the app (when app was not running)
        if let userActivity = connectionOptions.userActivities.first,
           userActivity.activityType == NSUserActivityTypeBrowsingWeb,
           let url = userActivity.webpageURL {
            handleIncomingURL(url)
        }
    }

    // Handle custom URL schemes when app is already running
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        handleIncomingURL(url)
    }

    // Handle Universal Links when app is already running
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else {
            return
        }
        handleIncomingURL(url)
    }

    // Centralized URL handling
    private func handleIncomingURL(_ url: URL) {
        Logger.info("Received deep link: \(url)")
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .deepLinkReceived,
                object: nil,
                userInfo: ["url": url]
            )
        }
    }

    // Called as the scene is being released by the system.
    func sceneDidDisconnect(_ scene: UIScene) {}

    // Called when the scene has moved from an inactive state to an active state.
    func sceneDidBecomeActive(_ scene: UIScene) {}

    // Called when the scene will move from an active state to an inactive state.
    func sceneWillResignActive(_ scene: UIScene) {}

    // Called as the scene transitions from the background to the foreground.
    func sceneWillEnterForeground(_ scene: UIScene) {}

    // Called as the scene transitions from the foreground to the background.
    func sceneDidEnterBackground(_ scene: UIScene) {}
}
