import UserNotifications
// TODO: Import ConvosShared framework when added to project
// import ConvosShared

class NotificationService: UNNotificationServiceExtension {
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        if let bestAttemptContent = bestAttemptContent {
            // Parse the notification payload
            let userInfo = request.content.userInfo

            // TODO: Use shared helpers when framework is set up
            // let payload = PushNotificationHelpers.NotificationPayload(from: userInfo)
            // let updatedContent = PushNotificationHelpers.buildNotificationContent(from: payload)

            // For now, handle notification modification directly
            if let conversationId = userInfo["conversation_id"] as? String {
                bestAttemptContent.threadIdentifier = conversationId
            }

            // Handle different notification types
            if let notificationType = userInfo["type"] as? String {
                switch notificationType {
                case "message":
                    // Process message notification
                    if let senderName = userInfo["sender_name"] as? String,
                       let messageContent = userInfo["message_content"] as? String {
                        bestAttemptContent.title = senderName
                        bestAttemptContent.body = messageContent
                    }

                case "group_invite":
                    // Process group invitation
                    if let senderName = userInfo["sender_name"] as? String {
                        bestAttemptContent.title = "Group Invitation"
                        bestAttemptContent.body = "\(senderName) invited you to a group"
                    }

                case "reaction":
                    // Process reaction notification
                    if let senderName = userInfo["sender_name"] as? String {
                        bestAttemptContent.title = "New Reaction"
                        bestAttemptContent.body = "\(senderName) reacted to your message"
                    }

                default:
                    break
                }
            }

            // TODO: Download and attach media if needed
            // This is where you'd download images/videos and attach them to the notification

            contentHandler(bestAttemptContent)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content,
        // otherwise the original push payload will be used.
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
}
