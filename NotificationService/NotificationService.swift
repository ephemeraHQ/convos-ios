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

        do {
            pushHandler = try NotificationExtensionEnvironment.createPushNotificationHandler()
        } catch {
            Logger.error("Error creating push notification handler: \(error.localizedDescription)")
        }

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

        Logger.info("NSE: Extension time expiring, cleaning up XMTP resources")
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
                // Cleanup and don't deliver any notification
                Logger.info("NSE: Cleaning up XMTP resources after dropping notification")
                pushHandler?.cleanup()
                return
            }
            // For other errors, continue with generic notification
            Logger.error("Push notification processing error: \(error)")
        }

        // Check if the task was cancelled before calling contentHandler
        guard !Task.isCancelled else {
            Logger.info("NSE: Task cancelled, cleaning up XMTP resources")
            pushHandler?.cleanup()
            return
        }

        // After processing, update with decoded content if available
        updateNotificationContentWithDecodedData(userInfo: userInfo)

        // Processing complete - cleanup resources before delivering notification
        Logger.info("NSE: Cleaning up XMTP resources after successful notification processing")
        pushHandler?.cleanup()

        // Deliver the notification
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

        // Get the processed payload with decoded content from the push handler
        if let processedPayload = pushHandler?.getProcessedPayload() {
            // Use the processed payload that contains decoded content
            if let title = processedPayload.displayTitleWithDecodedContent() {
                bestAttemptContent.title = title
            }

            if let body = processedPayload.displayBodyWithDecodedContent() {
                bestAttemptContent.body = body
            }

            Logger.info("Applied decoded notification content - Title: \(bestAttemptContent.title), Body: \(bestAttemptContent.body)")
        } else {
            // Fallback to creating new payload if processed payload not available
            let payload = PushNotificationPayload(userInfo: userInfo)

            if let title = payload.displayTitleWithDecodedContent() {
                bestAttemptContent.title = title
            }

            if let body = payload.displayBodyWithDecodedContent() {
                bestAttemptContent.body = body
            }

            Logger.info("Applied fallback notification content - Title: \(bestAttemptContent.title), Body: \(bestAttemptContent.body)")
        }
    }
}
