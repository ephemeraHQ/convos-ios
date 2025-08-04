import Foundation

public struct NotificationConstants {
    // Storage keys
    public struct StorageKeys {
        public static let deviceToken = "push_notification_device_token"
        public static let lastRegistrationDate = "push_notification_last_registration"
        public static let subscribedTopics = "push_notification_subscribed_topics"
        public static let conversationMessagesPrefix = "conversation_messages_"
        public static let userProfiles = "user_profiles_cache"
    }

    // Notification configuration
    public static let maxStoredMessagesPerConversation = 20

    // XMTP-specific constants
    public struct XMTP {
        public static let maxRetries = 3
        public static let retryDelay: TimeInterval = 1.0
    }
}
