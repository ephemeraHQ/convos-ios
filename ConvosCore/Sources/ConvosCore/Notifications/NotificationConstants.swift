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

    // App-level in-process notifications
    struct AppNotifications {
        static let pushTokenDidChange: String = "convosPushTokenDidChange"
        static let conversationUnsubscribeRequested: String = "convosConversationUnsubscribeRequested"
        static let unregisterAllInboxesRequested: String = "convosUnregisterAllInboxesRequested"
    }
}

extension Notification.Name {
    static let convosPushTokenDidChange: Notification.Name = Notification.Name(NotificationConstants.AppNotifications.pushTokenDidChange)
    static let convosConversationUnsubscribeRequested: Notification.Name = Notification.Name(NotificationConstants.AppNotifications.conversationUnsubscribeRequested)
    static let convosUnregisterAllInboxesRequested: Notification.Name = Notification.Name(NotificationConstants.AppNotifications.unregisterAllInboxesRequested)
}
