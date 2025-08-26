import ConvosCore
import Foundation
import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    private var pushHandler: CachedPushNotificationHandler?
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?
    private var pendingTask: Task<Void, Never>?
    private var requestId: String = ""
    private var didDeliverNotification: Bool = false

    private func logWithRequestId(_ message: String) {
        Logger.info("[RequestID: \(requestId)] \(message)")
    }

    private func deliverEmptyNotification() {
        guard !didDeliverNotification, let contentHandler = contentHandler else { return }
        let emptyContent = UNMutableNotificationContent()
        contentHandler(emptyContent)
        didDeliverNotification = true
    }

    private func configureLogging() {
        // Configure Logger with environment from stored configuration
        do {
            let environment = try NotificationExtensionEnvironment.getEnvironment()
            // Set production mode BEFORE configuring to avoid verbose logs in production
            switch environment {
            case .production:
                Logger.Default.configureForProduction(true)
            default:
                Logger.Default.configureForProduction(false)
            }
            Logger.configure(environment: environment)
        } catch {
            // Fallback: just log the error but continue
            print("NSE: Failed to configure logging with environment: \(error)")
        }
    }

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.requestId = request.identifier
        let processId = ProcessInfo.processInfo.processIdentifier

        // Configure Logger with environment from stored configuration
        configureLogging()

        Logger.info("[PID: \(processId)] [RequestID: \(requestId)] NSE: didReceive notification request")

        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        do {
            pushHandler = try NotificationExtensionEnvironment.createPushNotificationHandler()
            logWithRequestId("NSE: Push notification handler created successfully")
        } catch {
            logWithRequestId("NSE: Error creating push notification handler: \(error.localizedDescription)")
        }

        // Handle the push notification asynchronously and wait for completion
        logWithRequestId("NSE: Starting async notification processing")
        pendingTask = Task {
            await handlePushNotification(userInfo: request.content.userInfo)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system
        // Cancel any ongoing async work to prevent multiple contentHandler calls
        logWithRequestId("NSE: serviceExtensionTimeWillExpire called - extension about to be terminated")

        pendingTask?.cancel()
        pendingTask = nil

        logWithRequestId("NSE: Extension time expiring, cleaning up XMTP resources")
        pushHandler?.cleanup()

        // With notification filtering entitlement, deliver an empty notification to suppress display
        logWithRequestId("NSE: Timeout - delivering empty notification")
        deliverEmptyNotification()
    }

    private func handlePushNotification(userInfo: [AnyHashable: Any]) async {
        // Don't set initial content yet - wait to see if we should drop the notification
        logWithRequestId("NSE: Starting handlePushNotification processing")

        do {
            logWithRequestId("NSE: Calling pushHandler.handlePushNotification")
            try await pushHandler?.handlePushNotification(userInfo: userInfo)
            logWithRequestId("NSE: Push handler processing completed successfully")

            // Only set initial content if we're going to show the notification
            updateNotificationContent(userInfo: userInfo)
        } catch {
            // Check if this is a message that should be dropped
            if let error = error as? NotificationError, error == .messageShouldBeDropped {
                logWithRequestId("NSE: Notification dropped - message from self or non-text")
                logWithRequestId("NSE: Cleaning up XMTP resources after dropping notification")
                pushHandler?.cleanup()
                // Deliver empty notification (suppresses display)
                deliverEmptyNotification()
                return
            }
            // For any other errors, also drop the notification
            // Better to show nothing than generic/incorrect content
            logWithRequestId("NSE: Push notification processing error: \(error)")
            logWithRequestId("NSE: Dropping notification due to processing error")
            pushHandler?.cleanup()
            deliverEmptyNotification()
            return
        }

        // Check if the task was cancelled before calling contentHandler
        guard !Task.isCancelled else {
            logWithRequestId("NSE: Task cancelled, cleaning up XMTP resources")
            pushHandler?.cleanup()
            logWithRequestId("NSE: Dropping notification - task was cancelled")
            deliverEmptyNotification()
            return
        }

        // After processing, update with decoded content if available
        logWithRequestId("NSE: Updating notification content with decoded data")
        updateNotificationContentWithDecodedData(userInfo: userInfo)

        // Processing complete - cleanup resources before delivering notification
        logWithRequestId("NSE: Cleaning up XMTP resources after successful notification processing")
        pushHandler?.cleanup()

        // Deliver the notification
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            logWithRequestId("NSE: Delivering notification to system")
            contentHandler(bestAttemptContent)
            didDeliverNotification = true
        } else {
            logWithRequestId("NSE: Warning - contentHandler or bestAttemptContent is nil, delivering empty notification")
            deliverEmptyNotification()
        }
    }

    private func updateNotificationContent(userInfo: [AnyHashable: Any]) {
        guard let bestAttemptContent = bestAttemptContent else {
            logWithRequestId("NSE: updateNotificationContent - bestAttemptContent is nil")
            return
        }

        logWithRequestId("NSE: Updating notification content with basic payload data")
        let payload = PushNotificationPayload(userInfo: userInfo)

        // Use the basic display logic first
        if let displayTitle = payload.displayTitle {
            bestAttemptContent.title = displayTitle
            let length = displayTitle.count
            logWithRequestId("NSE: Notification title present=true length=\(length)")
        }

        if let displayBody = payload.displayBody {
            bestAttemptContent.body = displayBody
            let length = displayBody.count
            logWithRequestId("NSE: Notification body present=true length=\(length)")
        }

        // Set thread identifier for conversation grouping
        if let conversationId = payload.notificationData?.protocolData?.conversationId {
            bestAttemptContent.threadIdentifier = conversationId
            logWithRequestId("NSE: Set thread identifier: \(conversationId)")
        }
    }

    private func updateNotificationContentWithDecodedData(userInfo: [AnyHashable: Any]) {
        guard let bestAttemptContent = bestAttemptContent else {
            logWithRequestId("NSE: updateNotificationContentWithDecodedData - bestAttemptContent is nil")
            return
        }

        // Get the processed payload with decoded content from the push handler
        if let processedPayload = pushHandler?.getProcessedPayload() {
            logWithRequestId("NSE: Using processed payload with decoded content")
            // Use the processed payload that contains decoded content
            if let title = processedPayload.displayTitleWithDecodedContent() {
                bestAttemptContent.title = title
                logWithRequestId("NSE: Decoded title present=true length=\(title.count)")
            }

            if let body = processedPayload.displayBodyWithDecodedContent() {
                bestAttemptContent.body = body
                logWithRequestId("NSE: Decoded body present=true length=\(body.count)")
            }

            logWithRequestId("NSE: Applied decoded notification content")
        } else {
            logWithRequestId("NSE: No processed payload available, using fallback")
            // Fallback to creating new payload if processed payload not available
            let payload = PushNotificationPayload(userInfo: userInfo)

            if let title = payload.displayTitleWithDecodedContent() {
                bestAttemptContent.title = title
                logWithRequestId("NSE: Fallback title present=true length=\(title.count)")
            }

            if let body = payload.displayBodyWithDecodedContent() {
                bestAttemptContent.body = body
                logWithRequestId("NSE: Fallback body present=true length=\(body.count)")
            }

            logWithRequestId("NSE: Applied fallback notification content")
        }
    }
}
