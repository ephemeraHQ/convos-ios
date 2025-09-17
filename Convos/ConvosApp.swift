import ConvosCore
import SwiftUI
import UserNotifications

@main
struct ConvosApp: App {
    @UIApplicationDelegateAdaptor(ConvosAppDelegate.self) private var appDelegate: ConvosAppDelegate
    @Environment(\.scenePhase) private var scenePhase: ScenePhase
    @StateObject private var urlStorage: SceneURLStorage = SceneURLStorage.shared

    let session: any SessionManagerProtocol

    init() {
        let environment = ConfigManager.shared.currentEnvironment
        Logger.configure(environment: environment)

        switch environment {
        case .production:
            Logger.Default.configureForProduction(true)
        default:
            Logger.Default.configureForProduction(false)
        }

        Logger.info("App starting with environment: \(environment)")

        let convos: ConvosClient = .client(environment: environment)
        self.session = convos.session

        if let url = ConfigManager.shared.currentEnvironment.firebaseConfigURL {
            FirebaseHelperCore.configure(with: url)
        } else {
            Logger.error("Missing Firebase plist URL for current environment")
        }
    }

    var body: some Scene {
        WindowGroup {
            ConversationsView(session: session)
                .withSafeAreaEnvironment()
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onAppear {
                    // Pass session to app delegate for notification handling
                    appDelegate.session = session

                    // Process any pending URLs from cold launch
                    if let pendingURL = urlStorage.consumePendingURL() {
                        Logger.info("Processing pending URL from cold launch")
                        processDeepLink(pendingURL)
                    }
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
    }

    private func handleDeepLink(_ url: URL) {
        // Validate URL before processing
        guard DeepLinkHandler.destination(for: url) != nil else {
            Logger.warning("Invalid deep link received and ignored: [scheme: \(url.scheme ?? "unknown"), host: \(url.host ?? "unknown")]")
            return
        }

        Logger.info("Received valid deep link: [scheme: \(url.scheme ?? "unknown"), host: \(url.host ?? "unknown")]")

        // If app is in background, defer processing until it becomes active
        if scenePhase == .background {
            Logger.info("App in background - deferring deep link processing")
            urlStorage.storePendingURL(url)
            return
        }

        processDeepLink(url)
    }

    private func processDeepLink(_ url: URL) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .deepLinkReceived,
                object: nil,
                userInfo: ["url": url]
            )
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            Logger.info("App became active")
            // Process any pending deep links now that app is active and stable
            if let pendingURL = urlStorage.consumePendingURL() {
                Logger.info("Processing pending deep link")
                processDeepLink(pendingURL)
            }
        case .inactive:
            Logger.info("App became inactive")
        case .background:
            Logger.info("App moved to background")
        @unknown default:
            break
        }
    }
}

// Lightweight delegate for push notifications and Universal Links
@MainActor
class ConvosAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, ObservableObject {
    var session: (any SessionManagerProtocol)?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Scene configuration - required for Camera app Universal Links to work
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = ConvosSceneDelegate.self
        return configuration
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()

        Logger.info("Received device token from APNS: \(token)")
        // Store token in shared storage
        PushNotificationRegistrar.save(token: token)
        Logger.info("Stored device token in shared storage")

        // Notify listeners that token changed so session-ready components can push it to backend
        NotificationCenter.default.post(name: .convosPushTokenDidChange, object: nil)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Logger.error("Failed to register for remote notifications: \(error)")
    }

    // MARK: - UNUserNotificationCenterDelegate

    // Handle notifications when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // Check if we should display this notification based on the active conversation
        let conversationId = notification.request.content.threadIdentifier

        if !conversationId.isEmpty,
           let session = session {
            let shouldDisplay = await session.shouldDisplayNotification(for: conversationId)
            if !shouldDisplay {
                return []
            }
        }

        // Show notification banner when app is in foreground
        // NSE processes all notifications regardless of app state
        Logger.info("App in foreground - showing notification banner")
        return [.banner]
    }

    // Handle notification taps
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        Logger.debug("Notification tapped")

        // Parse the push notification payload to extract conversation info
        let payload = PushNotificationPayload(userInfo: userInfo)

        // Check if this is an explosion notification
        if let notificationType = userInfo["notificationType"] as? String,
           notificationType == "explosion",
           let inboxId = userInfo["inboxId"] as? String,
           let conversationId = userInfo["conversationId"] as? String {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .explosionNotificationTapped,
                    object: nil,
                    userInfo: [
                        "inboxId": inboxId,
                        "conversationId": conversationId,
                        "notificationType": notificationType
                    ]
                )
            }
            return
        }

        // Handle regular conversation notifications (Protocol messages)
        let conversationId = response.notification.request.content.threadIdentifier
        if let inboxId = payload.inboxId {
            Logger.info("Handling conversation notification tap for inboxId: \(inboxId), conversationId: \(conversationId)")
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .conversationNotificationTapped,
                    object: nil,
                    userInfo: [
                        "inboxId": inboxId,
                        "conversationId": conversationId
                    ]
                )
            }
        } else {
            Logger.warning("Notification tapped but could not extract conversation info from payload")
        }
    }
}
