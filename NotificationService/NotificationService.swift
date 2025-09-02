import ConvosCore
import Foundation
import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    private lazy var pushHandler: CachedPushNotificationHandler? = {
        do {
            return try NotificationExtensionEnvironment.createPushNotificationHandler()
        } catch {
            Logger.error("Error initializing push notification handler: \(error.localizedDescription)")
            return nil
        }
    }()

    private var pendingTask: Task<Void, Never>?

    private func configureLogging() {
        // Configure Logger with environment from stored configuration
        do {
            let environment = try NotificationExtensionEnvironment.getEnvironment()
            let isProd: Bool
            switch environment {
            case .production: isProd = true
            default: isProd = false
            }
            Logger.configure(environment: environment, isProduction: isProd)
        } catch {
            // Fallback: just log the error but continue
            print("Failed to configure logging with environment: \(error)")
        }
    }

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        let requestId = request.identifier
        let processId = ProcessInfo.processInfo.processIdentifier

        // Configure Logger with environment from stored configuration
        configureLogging()

        Logger.info("[PID: \(processId)] [RequestID: \(requestId)] didReceive notification request")

        guard let pushHandler else {
            Logger.error("No push notification handler available")
            contentHandler(UNMutableNotificationContent())
            return
        }

        // Handle the push notification asynchronously and wait for completion
        Logger.info("Starting async notification processing")
        pendingTask = Task {
            do {
                let payload = PushNotificationPayload(userInfo: request.content.userInfo)
                let decodedContent = try await pushHandler.handlePushNotification(
                    payload: payload
                )
                let shouldDropMessage = decodedContent?.isDroppedMessage ?? false
                if shouldDropMessage {
                    contentHandler(UNMutableNotificationContent())
                } else {
                    let notificationContent = decodedContent?.notificationContent ?? payload.undecodedNotificationContent
                    contentHandler(notificationContent)
                }
            } catch {
                Logger.error("Error processing notification: \(error.localizedDescription)")
                contentHandler(UNMutableNotificationContent())
            }
        }
    }

    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system
        // Cancel any ongoing async work to prevent multiple contentHandler calls
        Logger.info("serviceExtensionTimeWillExpire called - extension about to be terminated")
        // With notification filtering entitlement, deliver an empty notification to suppress display
        Logger.info("Timeout - delivering empty notification")
//        contentHandler(UNMutableNotificationContent())
    }
}

extension DecodedNotificationContent {
    var notificationContent: UNNotificationContent {
        let content = UNMutableNotificationContent()
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

        // Set thread identifier for conversation grouping
        if let conversationId = notificationData?.protocolData?.conversationId {
            content.threadIdentifier = conversationId
        }

        return content
    }
}
