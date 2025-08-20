import ConvosCore
import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    private var pushHandler: CachedPushNotificationHandler?
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?
    private var pendingTask: Task<Void, Never>?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        pushHandler = NotificationExtensionEnvironment.createPushNotificationHandler()

        // Handle the push notification asynchronously and wait for completion
        pendingTask = Task {
            await handlePushNotificationAsync(userInfo: request.content.userInfo)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system
        // Cancel any ongoing async work to prevent multiple contentHandler calls
        pendingTask?.cancel()
        pendingTask = nil

        pushHandler?.cleanup()

        // Deliver the best attempt content
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

    private func handlePushNotificationAsync(userInfo: [AnyHashable: Any]) async {
        // Update notification content before processing
        updateNotificationContent(userInfo: userInfo)

        // Use the async version that waits for completion
        await pushHandler?.handlePushNotificationAsync(userInfo: userInfo)

        // Check if the task was cancelled before calling contentHandler
        guard !Task.isCancelled else {
            return
        }

        // Processing complete - deliver the notification
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

        private func updateNotificationContent(userInfo: [AnyHashable: Any]) {
        guard let bestAttemptContent = bestAttemptContent else { return }

        let payload = PushNotificationPayload(userInfo: userInfo)

        // Use the centralized display logic from PushNotificationPayload
        if let displayTitle = payload.displayTitle {
            bestAttemptContent.title = displayTitle
        }

        if let displayBody = payload.displayBody {
            bestAttemptContent.body = displayBody
        }
    }
}
