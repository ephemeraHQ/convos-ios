import ConvosCore
import Foundation
import UserNotifications

// MARK: - Global Push Handler Singleton
// Shared across all NSE process instances for efficiency and thread safety
// The actor ensures thread-safe access from multiple notification deliveries
private let globalPushHandler: CachedPushNotificationHandler? = {
    do {
        // Configure logging first
        let environment = try NotificationExtensionEnvironment.getEnvironment()
        let isProd: Bool
        switch environment {
        case .production: isProd = true
        default: isProd = false
        }
        Logger.configure(environment: environment, isProduction: isProd)
        Logger.info("[NotificationService] Initializing global push handler for environment: \(environment.name)")

        // Create the handler
        return try NotificationExtensionEnvironment.createPushNotificationHandler()
    } catch {
        // Log to both console and Logger in case Logger isn't configured
        let errorMsg = "[NotificationService] Failed to initialize global push handler: \(error.localizedDescription)"
        print(errorMsg)
        Logger.error(errorMsg)
        return nil
    }
}()

class NotificationService: UNNotificationServiceExtension {
    // Keep track of the current processing task for cancellation
    private var currentProcessingTask: Task<Void, Never>?

    // Store content handler for timeout scenario
    private var contentHandler: ((UNNotificationContent) -> Void)?

    // Track lifecycle for debugging
    private let instanceId: Substring = UUID().uuidString.prefix(8)
    private let processId: Int32 = ProcessInfo.processInfo.processIdentifier

        override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        let requestId = request.identifier

        // Store content handler for timeout scenario
        self.contentHandler = contentHandler

        Logger.info("[PID: \(processId)] [Instance: \(instanceId)] [Request: \(requestId)] Starting notification processing")

        guard let pushHandler = globalPushHandler else {
            Logger.error("No global push handler available - suppressing notification")
            // Deliver empty notification to suppress display
            if let handler = self.contentHandler {
                handler(UNMutableNotificationContent())
                self.contentHandler = nil
            }
            return
        }

        // Cancel any previous task if still running (shouldn't happen but be safe)
        currentProcessingTask?.cancel()

        // Create a new processing task
        currentProcessingTask = Task { [weak self] in
            guard let self = self else { return }

            do {
                // Check for early cancellation
                try Task.checkCancellation()

                let payload = PushNotificationPayload(userInfo: request.content.userInfo)
                Logger.info("Processing notification")

                // Process the notification with the global handler
                let decodedContent = try await pushHandler.handlePushNotification(payload: payload)

                // Check for cancellation before delivering
                try Task.checkCancellation()

                // Determine what content to deliver
                let shouldDropMessage = decodedContent?.isDroppedMessage ?? false
                if shouldDropMessage {
                    Logger.info("Dropping notification as requested")
                    // Use self.contentHandler to avoid race condition with serviceExtensionTimeWillExpire
                    if let handler = self.contentHandler {
                        handler(UNMutableNotificationContent())
                        self.contentHandler = nil
                    }
                } else {
                    let notificationContent = decodedContent?.notificationContent ?? payload.undecodedNotificationContent
                    Logger.info("Delivering processed notification")
                    // Use self.contentHandler to avoid race condition with serviceExtensionTimeWillExpire
                    if let handler = self.contentHandler {
                        handler(notificationContent)
                        self.contentHandler = nil
                    }
                }
            } catch is CancellationError {
                Logger.info("Notification processing was cancelled")
                // Don't call contentHandler here - serviceExtensionTimeWillExpire will handle it

            } catch {
                Logger.error("Error processing notification: \(error)")
                // On error, suppress the notification by delivering empty content
                // Use self.contentHandler to avoid race condition with serviceExtensionTimeWillExpire
                if let handler = self.contentHandler {
                    handler(UNMutableNotificationContent())
                    self.contentHandler = nil
                }
            }
        }
    }

        override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system
        Logger.warning("[Instance: \(instanceId)] Service extension time expiring")

        // Cancel any ongoing processing
        currentProcessingTask?.cancel()
        currentProcessingTask = nil

        // Always deliver empty notification on timeout to suppress display
        if let contentHandler = contentHandler {
            Logger.info("Timeout - suppressing notification with empty content")
            contentHandler(UNMutableNotificationContent())
            self.contentHandler = nil
        }
    }

        // MARK: - Helper Methods

    deinit {
        Logger.info("[Instance: \(instanceId)] NotificationService instance deallocated")
    }
}

extension DecodedNotificationContent {
    var notificationContent: UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.userInfo = userInfo
        if let title {
            content.title = title
        }
        content.body = body
        if let conversationId {
            content.threadIdentifier = conversationId
        }
        return content
    }
}

// What we show when the notification fails to decode/process
extension PushNotificationPayload {
    var undecodedNotificationContent: UNNotificationContent {
        let content = UNMutableNotificationContent()

        // Use the basic display logic first
        if let displayTitle = displayTitle {
            content.title = displayTitle
        }

        if let displayBody = displayBody {
            content.body = displayBody
        }

        content.userInfo = userInfo

        // Set thread identifier for conversation grouping
        if let conversationId = notificationData?.protocolData?.conversationId {
            content.threadIdentifier = conversationId
        }

        return content
    }
}
