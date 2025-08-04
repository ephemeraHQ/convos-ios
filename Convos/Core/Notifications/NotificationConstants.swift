import Foundation

struct NotificationConstants {
    // Storage keys
    struct StorageKeys {
        static let deviceToken = "push_notification_device_token"
        static let lastRegistrationDate = "push_notification_last_registration"
        static let subscribedTopics = "push_notification_subscribed_topics"
        static let conversationMessagesPrefix = "conversation_messages_"
        static let userProfiles = "user_profiles_cache"
    }

    // Notification configuration
    static let maxStoredMessagesPerConversation = 20

    // XMTP-specific constants
    struct XMTP {
        static let maxRetries = 3
        static let retryDelay: TimeInterval = 1.0
    }
}