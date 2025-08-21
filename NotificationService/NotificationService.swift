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
        // Set initial notification content
        updateNotificationContent(userInfo: userInfo)

        // Use the async version that waits for completion (this will decode the message)
        do {
            try await pushHandler?.handlePushNotificationAsync(userInfo: userInfo)
        } catch {
            // Check if this is a message that should be dropped
            if let error = error as? NotificationError, error == .messageShouldBeDropped {
                Logger.info("Notification dropped - message from self or non-text")
                // Don't deliver any notification
                return
            }
            // For other errors, continue with generic notification
            Logger.error("Push notification processing error: \(error)")
        }

        // Check if the task was cancelled before calling contentHandler
        guard !Task.isCancelled else {
            return
        }

        // After processing, update with decoded content if available
        updateNotificationContentWithDecodedData(userInfo: userInfo)

        // Processing complete - deliver the notification
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

    private func updateNotificationContent(userInfo: [AnyHashable: Any]) {
        guard let bestAttemptContent = bestAttemptContent else { return }

        let payload = PushNotificationPayload(userInfo: userInfo)

        // Use the basic display logic first
        if let displayTitle = payload.displayTitle {
            bestAttemptContent.title = displayTitle
        }

        if let displayBody = payload.displayBody {
            bestAttemptContent.body = displayBody
        }

        // Set thread identifier for conversation grouping
        if let conversationId = payload.notificationData?.protocolData?.conversationId {
            bestAttemptContent.threadIdentifier = conversationId
        }
    }

    private func updateNotificationContentWithDecodedData(userInfo: [AnyHashable: Any]) {
        guard let bestAttemptContent = bestAttemptContent else { return }

        let payload = PushNotificationPayload(userInfo: userInfo)

        // Get the app group identifier from the environment
        let environment = NotificationExtensionEnvironment.getEnvironment()
        let appGroupIdentifier = environment.appGroupIdentifier

        // Use the enhanced display logic that includes decoded content
        if let displayTitle = payload.displayTitleWithDecodedContent(appGroupIdentifier: appGroupIdentifier) {
            bestAttemptContent.title = displayTitle
        }

        if let displayBody = payload.displayBodyWithDecodedContent(appGroupIdentifier: appGroupIdentifier) {
            bestAttemptContent.body = displayBody
        }
    }
}
