import ConvosCore
import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    private var pushHandler: CachedPushNotificationHandler?
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        pushHandler = NotificationExtensionEnvironment.createPushNotificationHandler()

        // Handle the push notification asynchronously and wait for completion
        Task {
            await handlePushNotificationAsync(userInfo: request.content.userInfo)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system
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

        // Processing complete - deliver the notification
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

    private func updateNotificationContent(userInfo: [AnyHashable: Any]) {
        guard let bestAttemptContent = bestAttemptContent else { return }

        let payload = PushNotificationPayload(userInfo: userInfo)

        // Only update for invite join requests
        guard payload.notificationType == .inviteJoinRequest,
              let inviteData = payload.notificationData?.inviteData else {
            return
        }

        // Get the requester name
        let requesterName = inviteData.requester?.profile?.displayNameOrUsername ?? "Someone"

        // Get the group name
        let groupName = inviteData.inviteCode?.displayName ?? "your group"

        // Create the appropriate message based on auto-approve status
        let message: String
        if inviteData.autoApprove {
            message = "\(requesterName) joined \(groupName)"
        } else {
            message = "\(requesterName) requested to join \(groupName)"
        }

        // Update the notification content
        bestAttemptContent.body = message
    }
}
