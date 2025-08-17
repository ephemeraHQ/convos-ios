import ConvosCore
import Foundation
import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        Logger.info("🔔 NSE Activating: didReceive")

        if let bestAttemptContent = bestAttemptContent {
            // Parse the notification payload
            let userInfo = request.content.userInfo

            // Log the raw payload received by the NSE (visible in Console.app)
            logNSEPayload(userInfo)

            let inboxId = userInfo["inboxId"] as? String
            if let inboxId {
                Logger.info("NSE: inboxId=\(inboxId)")
            }

            if let notificationType = userInfo["notificationType"] as? String {
                switch notificationType {
                case "Protocol":
                    // Expect notificationData dict with contentTopic and encryptedMessage
                    if let data = userInfo["notificationData"] as? [String: Any] {
                        let contentTopic = data["contentTopic"] as? String
                        if let topic = contentTopic,
                           let conversationId = topic.conversationIdFromXMTPGroupTopic {
                            bestAttemptContent.threadIdentifier = conversationId

                            // Set a simple body if none present
                            if bestAttemptContent.body.isEmpty { bestAttemptContent.body = "New message" }
                        }
                        // Keep title/body if backend provided; extension does not decrypt
                        NSLog("NSE Protocol: topic=%@", contentTopic ?? "nil")
                    }

                case "InviteJoinRequest":
                    // Expect notificationData with requester.profile.username, inviteCode.name, autoApprove
                    bestAttemptContent.title = "Group Invitation"

                    var displayName = "Someone"
                    var groupName = "your group"

                    if let data = userInfo["notificationData"] as? [String: Any] {
                        if let requester = data["requester"] as? [String: Any],
                        let profile = requester["profile"] as? [String: Any],
                        let username = profile["username"] as? String,
                        !username.isEmpty {
                            displayName = username
                        }

                        if let inviteCode = data["inviteCode"] as? [String: Any],
                        let name = inviteCode["name"] as? String,
                        !name.isEmpty {
                            groupName = name
                        }

                        let autoApprove = data["autoApprove"] as? Bool ?? false
                        if autoApprove {
                            bestAttemptContent.body = "\(displayName) joined \(groupName)"
                        } else {
                            bestAttemptContent.body = "\(displayName) requested to join \(groupName)"
                        }
                    } else {
                        // Fallback copy if payload does not include expected fields
                        bestAttemptContent.body = "Someone requested to join your group"
                    }

                    // Thread by inbox if available so invites group in notification center
                    if let inboxId { bestAttemptContent.threadIdentifier = "invites-\(inboxId)" }

                default:
                    break
                }
            }

            contentHandler(bestAttemptContent)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content,
        // otherwise the original push payload will be used.
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            NSLog("NSE timeWillExpire - delivering best attempt content")
            contentHandler(bestAttemptContent)
        }
    }

    // MARK: - Logging
    private func logNSEPayload(_ userInfo: [AnyHashable: Any]) {
        // Try to serialize to JSON for readability; fall back to dictionary description
        if JSONSerialization.isValidJSONObject(userInfo),
           let data = try? JSONSerialization.data(withJSONObject: userInfo, options: [.prettyPrinted]),
           let json = String(data: data, encoding: .utf8) {
            Logger.info("NSE received push payload:\n\(json)")
        } else {
            Logger
                .info(
                    "NSE received push payload (non-JSON): \(String(describing: userInfo))"
                )
        }
    }
}
