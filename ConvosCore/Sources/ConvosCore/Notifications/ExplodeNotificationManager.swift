import Foundation
import UserNotifications

/// Manages local notifications for scheduled conversation explosions
public final class ExplodeNotificationManager {

    // MARK: - Constants

    private enum Constants {
        static let notificationCategoryIdentifier = "EXPLODE_CONVERSATION"
        static let notificationActionIdentifier = "EXPLODE_ACTION"
        static let conversationIdKey = "conversationId"
        static let inboxIdKey = "inboxId"
        static let clientIdKey = "clientId"
    }

    // MARK: - Public Methods

    /// Schedules a local notification to explode a conversation at the specified date
    /// - Parameters:
    ///   - conversationId: The ID of the conversation to explode
    ///   - inboxId: The inbox ID associated with the conversation
    ///   - clientId: The client ID associated with the conversation
    ///   - expiresAt: The date when the conversation should explode
    public static func scheduleExplodeNotification(
        conversationId: String,
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
        content.title = "Conversation Expired"
        content.body = "A conversation has reached its expiration time and will be deleted."
        content.categoryIdentifier = Constants.notificationCategoryIdentifier
        content.userInfo = [
            Constants.conversationIdKey: conversationId,
            Constants.inboxIdKey: inboxId,
            Constants.clientIdKey: clientId
        ]

        // Don't show alert or play sound - this is a background operation
        content.interruptionLevel = .passive

        // Create trigger based on expiration date
        let timeInterval = expiresAt.timeIntervalSinceNow
        guard timeInterval > 0 else {
            Log.warning("Cannot schedule explode notification for past date")
            return
        }

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: timeInterval,
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
                .filter { $0.content.categoryIdentifier == Constants.notificationCategoryIdentifier }
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
    /// - Returns: A tuple containing conversationId, inboxId, and clientId if found
    public static func extractConversationInfo(from request: UNNotificationRequest) -> (conversationId: String, inboxId: String, clientId: String)? {
        guard request.content.categoryIdentifier == Constants.notificationCategoryIdentifier else {
            return nil
        }

        let userInfo = request.content.userInfo
        guard let conversationId = userInfo[Constants.conversationIdKey] as? String,
              let inboxId = userInfo[Constants.inboxIdKey] as? String,
              let clientId = userInfo[Constants.clientIdKey] as? String else {
            return nil
        }

        return (conversationId, inboxId, clientId)
    }

    /// Checks if a notification response is for an explode notification
    /// - Parameter response: The notification response
    /// - Returns: Conversation info if this is an explode notification
    public static func extractConversationInfo(from response: UNNotificationResponse) -> (conversationId: String, inboxId: String, clientId: String)? {
        extractConversationInfo(from: response.notification.request)
    }

    // MARK: - Private Methods

    private static func explodeNotificationIdentifier(for conversationId: String) -> String {
        "explode_\(conversationId)"
    }
}
