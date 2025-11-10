import ConvosLogging
import Foundation
import UserNotifications

/// Information about a scheduled explosion
public struct ExplodeNotificationInfo {
    public let conversationId: String
    public let inboxId: String
    public let clientId: String
    public let expiresAt: Date

    public init(conversationId: String, inboxId: String, clientId: String, expiresAt: Date) {
        self.conversationId = conversationId
        self.inboxId = inboxId
        self.clientId = clientId
        self.expiresAt = expiresAt
    }
}

/// Manages local notifications for scheduled conversation explosions
public final class ExplodeNotificationManager {
    // MARK: - Constants

    private static let notificationCategoryIdentifier: String = "EXPLODE_CONVERSATION"
    private static let notificationActionIdentifier: String = "EXPLODE_ACTION"
    private static let conversationIdKey: String = "conversationId"
    private static let inboxIdKey: String = "inboxId"
    private static let clientIdKey: String = "clientId"
    private static let expiresAtKey: String = "expiresAt"

    // MARK: - Public Methods

    /// Schedules a local notification to explode a conversation at the specified date
    /// - Parameters:
    ///   - conversationId: The ID of the conversation to explode
    ///   - conversationName: The name of the conversation (optional)
    ///   - inboxId: The inbox ID associated with the conversation
    ///   - clientId: The client ID associated with the conversation
    ///   - expiresAt: The date when the conversation should explode
    public static func scheduleExplodeNotification(
        conversationId: String,
        conversationName: String?,
        inboxId: String,
        clientId: String,
        expiresAt: Date
    ) async throws {
        let notificationCenter = UNUserNotificationCenter.current()

        // Check if we have notification permissions
        let settings = await notificationCenter.notificationSettings()
        guard settings.authorizationStatus == .authorized else {
            Log.warning("Cannot schedule explode notification - not authorized")
            return
        }

        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "💥 \(conversationName ?? "Untitled") 💥"
        content.body = "A convo exploded"
        content.categoryIdentifier = notificationCategoryIdentifier
        content.userInfo = [
            conversationIdKey: conversationId,
            inboxIdKey: inboxId,
            clientIdKey: clientId,
            expiresAtKey: expiresAt.timeIntervalSince1970
        ]

        // Show alert and play sound for explode notifications
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        // Create trigger based on expiration date
        let now = Date()
        let timeInterval = expiresAt.timeIntervalSince(now)

        Log.info("ExplodeNotificationManager - expiresAt: \(expiresAt), now: \(now), timeInterval: \(timeInterval) seconds")

        // If the expiration time has already passed or is very close (< 1 second),
        // schedule for 1 second from now to ensure the notification fires
        let adjustedTimeInterval = max(timeInterval, 1.0)

        if timeInterval <= 0 {
            Log.warning("Expiration date is in the past (timeInterval: \(timeInterval)), scheduling for 1 second from now")
        } else if timeInterval < 1.0 {
            Log.info("Expiration date is very close (timeInterval: \(timeInterval)), adjusting to 1 second from now")
        }

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: adjustedTimeInterval,
            repeats: false
        )

        // Create request with unique identifier
        let requestIdentifier = explodeNotificationIdentifier(for: conversationId)
        let request = UNNotificationRequest(
            identifier: requestIdentifier,
            content: content,
            trigger: trigger
        )

        // Schedule the notification
        try await notificationCenter.add(request)
        Log.info("Scheduled explode notification for conversation \(conversationId) at \(expiresAt)")
    }

    /// Cancels a scheduled explode notification for a conversation
    /// - Parameter conversationId: The ID of the conversation
    public static func cancelExplodeNotification(for conversationId: String) {
        let notificationCenter = UNUserNotificationCenter.current()
        let identifier = explodeNotificationIdentifier(for: conversationId)

        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])

        Log.info("Cancelled explode notification for conversation \(conversationId)")
    }

    /// Cancels all scheduled explode notifications
    public static func cancelAllExplodeNotifications() {
        Task {
            let notificationCenter = UNUserNotificationCenter.current()
            let pendingRequests = await notificationCenter.pendingNotificationRequests()

            let explodeRequestIds = pendingRequests
                .filter { $0.content.categoryIdentifier == notificationCategoryIdentifier }
                .map { $0.identifier }

            if !explodeRequestIds.isEmpty {
                notificationCenter.removePendingNotificationRequests(withIdentifiers: explodeRequestIds)
                Log.info("Cancelled \(explodeRequestIds.count) explode notifications")
            }
        }
    }

    /// Checks if an explode notification is scheduled for a conversation
    /// - Parameter conversationId: The ID of the conversation
    /// - Returns: True if a notification is scheduled
    public static func isExplodeNotificationScheduled(for conversationId: String) async -> Bool {
        let notificationCenter = UNUserNotificationCenter.current()
        let identifier = explodeNotificationIdentifier(for: conversationId)

        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        return pendingRequests.contains { $0.identifier == identifier }
    }

    /// Extracts conversation metadata from a notification request
    /// - Parameter request: The notification request
    /// - Returns: ExplodeNotificationInfo if this is an explode notification
    public static func extractConversationInfo(from request: UNNotificationRequest) -> ExplodeNotificationInfo? {
        guard request.content.categoryIdentifier == notificationCategoryIdentifier else {
            return nil
        }

        let userInfo = request.content.userInfo
        guard let conversationId = userInfo[conversationIdKey] as? String,
              let inboxId = userInfo[inboxIdKey] as? String,
              let clientId = userInfo[clientIdKey] as? String,
              let expiresAtTimestamp = userInfo[expiresAtKey] as? TimeInterval else {
            return nil
        }

        let expiresAt = Date(timeIntervalSince1970: expiresAtTimestamp)

        return ExplodeNotificationInfo(
            conversationId: conversationId,
            inboxId: inboxId,
            clientId: clientId,
            expiresAt: expiresAt
        )
    }

    /// Checks if a notification response is for an explode notification
    /// - Parameter response: The notification response
    /// - Returns: ExplodeNotificationInfo if this is an explode notification
    public static func extractConversationInfo(from response: UNNotificationResponse) -> ExplodeNotificationInfo? {
        extractConversationInfo(from: response.notification.request)
    }

    // MARK: - Private Methods

    private static func explodeNotificationIdentifier(for conversationId: String) -> String {
        "explode_\(conversationId)"
    }
}
