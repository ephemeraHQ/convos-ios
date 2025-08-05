import Foundation

struct NotificationConstants {
    // Storage keys
    struct StorageKeys {
        static let deviceToken: String = "push_notification_device_token"
        static let lastRegistrationDate: String = "push_notification_last_registration"
        static let subscribedTopics: String = "push_notification_subscribed_topics"
        static let conversationMessagesPrefix: String = "conversation_messages_"
        static let userProfiles: String = "user_profiles_cache"
    }

    // Notification configuration
    static let maxStoredMessagesPerConversation: Int = 20

    // XMTP-specific constants
    struct XMTP {
        static let maxRetries: Int = 3
        static let retryDelay: TimeInterval = 1.0
    }
}
