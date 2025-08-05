import Foundation

public struct NotificationConstants {
    // Storage keys
    public struct StorageKeys {
        public static let deviceToken: String = "push_notification_device_token"
        public static let lastRegistrationDate: String = "push_notification_last_registration"
        public static let subscribedTopics: String = "push_notification_subscribed_topics"
        public static let conversationMessagesPrefix: String = "conversation_messages_"
        public static let userProfiles: String = "user_profiles_cache"
    }

    // Notification configuration
    public static let maxStoredMessagesPerConversation: Int = 20

    // XMTP-specific constants
    public struct XMTP {
        public static let maxRetries: Int = 3
        public static let retryDelay: TimeInterval = 1.0
    }
}
