import Foundation
import UserNotifications

class NotificationProcessor {
    static let shared = NotificationProcessor()

    private let appGroupIdentifier: String

    init(appGroupIdentifier: String) {
        self.appGroupIdentifier = appGroupIdentifier
    }

    private convenience init() {
        // For backward compatibility - should not be used directly
        fatalError("Use init(appGroupIdentifier:) instead")
    }

    private var appGroupDefaults: UserDefaults? {
        return UserDefaults(suiteName: appGroupIdentifier)
    }

    // MARK: - Notification Processing

    func processNotificationPayload(_ userInfo: [AnyHashable: Any]) throws -> NotificationPayload {
        let jsonData = try JSONSerialization.data(withJSONObject: userInfo, options: [])
        let decoder = JSONDecoder()
        return try decoder.decode(NotificationPayload.self, from: jsonData)
    }

    // MARK: - Message Storage

    func storeDecryptedMessage(
        _ messageData: [String: Any],
        conversationId: String
    ) throws {
        let storageKey = "\(NotificationConstants.StorageKeys.conversationMessagesPrefix)\(conversationId)"

        // Get existing messages
        var existingMessages: [[String: Any]] = []
        if let existingData = appGroupDefaults?.string(forKey: storageKey),
           let data = existingData.data(using: .utf8),
           let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            existingMessages = jsonArray
        }

        // Add new message at the beginning
        existingMessages.insert(messageData, at: 0)

        // Trim to max messages
        if existingMessages.count > NotificationConstants.maxStoredMessagesPerConversation {
            existingMessages = Array(existingMessages.prefix(NotificationConstants.maxStoredMessagesPerConversation))
        }

        // Save back to storage
        let jsonData = try JSONSerialization.data(withJSONObject: existingMessages)
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            appGroupDefaults?.set(jsonString, forKey: storageKey)
        }
    }

    func getStoredMessages(for conversationId: String) -> [[String: Any]]? {
        let storageKey = "\(NotificationConstants.StorageKeys.conversationMessagesPrefix)\(conversationId)"

        guard let existingData = appGroupDefaults?.string(forKey: storageKey),
              let data = existingData.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        return jsonArray
    }

    // MARK: - Device Token Management

    func storeDeviceToken(_ token: String) {
        appGroupDefaults?.set(token, forKey: NotificationConstants.StorageKeys.deviceToken)
        appGroupDefaults?.set(Date(), forKey: NotificationConstants.StorageKeys.lastRegistrationDate)
    }

    func getStoredDeviceToken() -> String? {
        return appGroupDefaults?.string(forKey: NotificationConstants.StorageKeys.deviceToken)
    }

    // MARK: - Topic Management

    func storeSubscribedTopics(_ topics: Set<String>) {
        let topicsArray = Array(topics)
        appGroupDefaults?.set(topicsArray, forKey: NotificationConstants.StorageKeys.subscribedTopics)
    }

    func getSubscribedTopics() -> Set<String> {
        let topicsArray = appGroupDefaults?.stringArray(forKey: NotificationConstants.StorageKeys.subscribedTopics) ?? []
        return Set(topicsArray)
    }

    func addSubscribedTopic(_ topic: String) {
        var topics = getSubscribedTopics()
        topics.insert(topic)
        storeSubscribedTopics(topics)
    }

    func removeSubscribedTopic(_ topic: String) {
        var topics = getSubscribedTopics()
        topics.remove(topic)
        storeSubscribedTopics(topics)
    }

    // MARK: - Notification Content Building

    func buildNotificationContent(from processedContent: ProcessedNotificationContent) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()

        content.title = processedContent.title
        if let subtitle = processedContent.subtitle {
            content.subtitle = subtitle
        }
        content.body = processedContent.body
        content.threadIdentifier = processedContent.threadIdentifier
        content.sound = .default

        // Add user info
        var userInfo = processedContent.userInfo
        userInfo["conversation_id"] = processedContent.threadIdentifier
        content.userInfo = userInfo

        // Add attachment if available
        if let attachmentURL = processedContent.attachmentURL,
           let attachment = try? UNNotificationAttachment(
               identifier: UUID().uuidString,
               url: attachmentURL,
               options: nil
           ) {
            content.attachments = [attachment]
        }

        return content
    }

    // MARK: - Conversation ID from Topic

    func getConversationIdFromTopic(_ topic: String) -> String {
        // XMTP topics have a specific format, extract conversation ID
        // This is a simplified version - adjust based on your actual topic format
        return topic
    }
}
