import Foundation
import UserNotifications

public struct PushNotificationHelpers {
    // MARK: - Token Formatting

    public static func formatDeviceToken(_ deviceToken: Data) -> String {
        return deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    }

    // MARK: - Notification Parsing

    public struct NotificationPayload {
        public let conversationId: String?
        public let messageId: String?
        public let senderId: String?
        public let senderName: String?
        public let messageContent: String?
        public let timestamp: Date?
        public let type: NotificationType

        public enum NotificationType: String {
            case message
            case groupInvite = "group_invite"
            case reaction
            case mention
            case unknown
        }

        public init(from userInfo: [AnyHashable: Any]) {
            // Parse your notification payload structure
            if let aps = userInfo["aps"] as? [String: Any] {
                // Standard APNS fields
                _ = aps["alert"]
                _ = aps["badge"]
                _ = aps["sound"]
            }

            // Custom payload fields
            self.conversationId = userInfo["conversation_id"] as? String
            self.messageId = userInfo["message_id"] as? String
            self.senderId = userInfo["sender_id"] as? String
            self.senderName = userInfo["sender_name"] as? String
            self.messageContent = userInfo["message_content"] as? String

            if let timestampString = userInfo["timestamp"] as? String,
               let timestampDouble = Double(timestampString) {
                self.timestamp = Date(timeIntervalSince1970: timestampDouble)
            } else {
                self.timestamp = nil
            }

            if let typeString = userInfo["type"] as? String {
                self.type = NotificationType(rawValue: typeString) ?? .unknown
            } else {
                self.type = .message
            }
        }
    }

    // MARK: - Notification Content Builders

    public static func buildNotificationContent(from payload: NotificationPayload) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()

        switch payload.type {
        case .message:
            content.title = payload.senderName ?? "New Message"
            content.body = payload.messageContent ?? "You have a new message"
            content.sound = .default

        case .groupInvite:
            content.title = "Group Invitation"
            content.body = "\(payload.senderName ?? "Someone") invited you to a group"
            content.sound = .default

        case .reaction:
            content.title = "New Reaction"
            content.body = "\(payload.senderName ?? "Someone") reacted to your message"
            content.sound = .default

        case .mention:
            content.title = payload.senderName ?? "Mention"
            content.body = payload.messageContent ?? "You were mentioned in a conversation"
            content.sound = .default

        case .unknown:
            content.title = "Convos"
            content.body = "You have a new notification"
            content.sound = .default
        }

        // Add conversation ID for deep linking
        if let conversationId = payload.conversationId {
            content.userInfo["conversation_id"] = conversationId
        }

        // Add thread identifier for grouping notifications
        content.threadIdentifier = payload.conversationId ?? "default"

        return content
    }

    // MARK: - Storage Keys

    public struct StorageKeys {
        public static let deviceToken: String = "push_notification_device_token"
        public static let lastRegistrationDate: String = "push_notification_last_registration"
        public static let subscribedTopics: String = "push_notification_subscribed_topics"
    }

    // MARK: - App Group Shared Storage

    public static let appGroupIdentifier: String = "group.com.convos.shared"

    public static var sharedUserDefaults: UserDefaults? {
        return UserDefaults(suiteName: appGroupIdentifier)
    }

    // MARK: - Shared Token Storage

    public static func saveDeviceToken(_ token: String) {
        sharedUserDefaults?.set(token, forKey: StorageKeys.deviceToken)
        sharedUserDefaults?.set(Date(), forKey: StorageKeys.lastRegistrationDate)
    }

    public static func getDeviceToken() -> String? {
        return sharedUserDefaults?.string(forKey: StorageKeys.deviceToken)
    }

    // MARK: - Topic Management

    public static func saveSubscribedTopics(_ topics: Set<String>) {
        let topicsArray = Array(topics)
        sharedUserDefaults?.set(topicsArray, forKey: StorageKeys.subscribedTopics)
    }

    public static func getSubscribedTopics() -> Set<String> {
        let topicsArray = sharedUserDefaults?.stringArray(forKey: StorageKeys.subscribedTopics) ?? []
        return Set(topicsArray)
    }
}
