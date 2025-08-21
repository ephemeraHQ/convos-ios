import Foundation

/// Represents the payload structure of a push notification
public struct PushNotificationPayload {
    public let inboxId: String?
    public let notificationType: NotificationType?
    public let notificationData: NotificationData?

    public init(userInfo: [AnyHashable: Any]) {
        self.inboxId = userInfo["inboxId"] as? String
        self.notificationType = NotificationType(rawValue: userInfo["notificationType"] as? String ?? "")
        self.notificationData = NotificationData(dictionary: userInfo["notificationData"] as? [String: Any])
    }
}

// MARK: - Notification Types

public enum NotificationType: String, CaseIterable {
    case protocolMessage = "Protocol"
    case inviteJoinRequest = "InviteJoinRequest"

    public var displayName: String {
        switch self {
        case .protocolMessage:
            return "Protocol Message"
        case .inviteJoinRequest:
            return "Invite Join Request"
        }
    }
}

// MARK: - Notification Data

public struct NotificationData {
    public let protocolData: ProtocolNotificationData?
    public let inviteData: InviteJoinRequestData?

    public init(dictionary: [String: Any]?) {
        guard let dict = dictionary else {
            self.protocolData = nil
            self.inviteData = nil
            return
        }

        self.protocolData = ProtocolNotificationData(dictionary: dict)
        self.inviteData = InviteJoinRequestData(dictionary: dict)
    }
}

// MARK: - Protocol Notification Data

public struct ProtocolNotificationData {
    public let contentTopic: String?
    public let encryptedMessage: String?

    public var conversationId: String? {
        guard let topic = contentTopic else { return nil }
        return topic.conversationIdFromXMTPGroupTopic
    }

    public init(dictionary: [String: Any]?) {
        guard let dict = dictionary else {
            self.contentTopic = nil
            self.encryptedMessage = nil
            return
        }

        self.contentTopic = dict["contentTopic"] as? String
        self.encryptedMessage = dict["encryptedMessage"] as? String
    }
}

// MARK: - Invite Join Request Data

public struct InviteJoinRequestData {
    public let requestId: String?
    public let requester: RequesterData?
    public let inviteCode: InviteCodeData?
    public let autoApprove: Bool

    public init(dictionary: [String: Any]?) {
        guard let dict = dictionary else {
            self.requestId = nil
            self.requester = nil
            self.inviteCode = nil
            self.autoApprove = false
            return
        }

        self.requestId = dict["id"] as? String ?? dict["requestId"] as? String
        self.requester = RequesterData(dictionary: dict["requester"] as? [String: Any])
        self.inviteCode = InviteCodeData(dictionary: dict["inviteCode"] as? [String: Any])
        self.autoApprove = dict["autoApprove"] as? Bool ?? false
    }
}

public struct RequesterData {
    public let id: String?
    public let xmtpId: String?
    public let profile: ProfileData?

    public init(dictionary: [String: Any]?) {
        guard let dict = dictionary else {
            self.id = nil
            self.xmtpId = nil
            self.profile = nil
            return
        }

        self.id = dict["id"] as? String
        self.xmtpId = dict["xmtpId"] as? String
        self.profile = ProfileData(dictionary: dict["profile"] as? [String: Any])
    }
}

public struct ProfileData {
    public let name: String?
    public let username: String?
    public let description: String?
    public let avatar: String?

    public init(dictionary: [String: Any]?) {
        guard let dict = dictionary else {
            self.name = nil
            self.username = nil
            self.description = nil
            self.avatar = nil
            return
        }

        self.name = dict["name"] as? String
        self.username = dict["username"] as? String
        self.description = dict["description"] as? String
        self.avatar = dict["avatar"] as? String
    }

    public var displayNameOrUsername: String {
        return name ?? username ?? "Someone"
    }
}

public struct InviteCodeData {
    public let id: String?
    public let name: String?
    public let groupId: String?

    public init(dictionary: [String: Any]?) {
        guard let dict = dictionary else {
            self.id = nil
            self.name = nil
            self.groupId = nil
            return
        }

        self.id = dict["id"] as? String
        self.name = dict["name"] as? String
        self.groupId = dict["groupId"] as? String
    }

    public var displayName: String {
        return name ?? "your group"
    }
}

// MARK: - Convenience Extensions

public extension PushNotificationPayload {
    /// Creates a thread identifier for grouping notifications
    var threadIdentifier: String? {
        switch notificationType {
        case .protocolMessage:
            return notificationData?.protocolData?.conversationId
        case .inviteJoinRequest:
            guard let inboxId = inboxId else { return nil }
            return "invites-\(inboxId)"
        case .none:
            return nil
        }
    }

    /// Generates a display title for the notification
    var displayTitle: String? {
        switch notificationType {
        case .inviteJoinRequest:
            return "Group Invitation"
        case .protocolMessage:
            return nil // Use default title
        case .none:
            return nil
        }
    }

    /// Generates a display body for the notification
    var displayBody: String? {
        switch notificationType {
        case .protocolMessage:
            return "New message"
        case .inviteJoinRequest:
            guard let inviteData = notificationData?.inviteData else {
                return "Someone requested to join your group"
            }

            let displayName = inviteData.requester?.profile?.displayNameOrUsername ?? "Someone"
            let groupName = inviteData.inviteCode?.displayName ?? "your group"

            if inviteData.autoApprove {
                return "\(displayName) joined \(groupName)"
            } else {
                return "\(displayName) requested to join \(groupName)"
            }
        case .none:
            return nil
        }
    }

    /// Generates a display title for the notification with decoded content
    /// - Parameter appGroupIdentifier: The app group identifier for shared storage
    /// - Returns: The display title with decoded content if available
    func displayTitleWithDecodedContent(appGroupIdentifier: String) -> String? {
        switch notificationType {
        case .protocolMessage:
            // Try to get decoded title from stored content
            if let decodedTitle = getDecodedTitle(appGroupIdentifier: appGroupIdentifier) {
                return decodedTitle
            }
            return displayTitle
        case .inviteJoinRequest:
            return displayTitle
        case .none:
            return nil
        }
    }

    /// Generates a display body for the notification with decoded content
    /// - Parameter appGroupIdentifier: The app group identifier for shared storage
    /// - Returns: The display body with decoded content if available
    func displayBodyWithDecodedContent(appGroupIdentifier: String) -> String? {
        switch notificationType {
        case .protocolMessage:
            // Try to get decoded body from stored content
            if let decodedBody = getDecodedBody(appGroupIdentifier: appGroupIdentifier) {
                return decodedBody
            }
            return displayBody
        case .inviteJoinRequest:
            return displayBody
        case .none:
            return nil
        }
    }

    // MARK: - Private Helpers

    /// Gets decoded title from stored content if available
    private func getDecodedTitle(appGroupIdentifier: String) -> String? {
        guard let conversationId = notificationData?.protocolData?.conversationId else {
            return nil
        }

        let storageKey = "decoded_notification_\(conversationId)"

        guard let appGroupDefaults = UserDefaults(suiteName: appGroupIdentifier),
              let jsonString = appGroupDefaults.string(forKey: storageKey),
              let data = jsonString.data(using: .utf8),
              let notificationData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Return title if available, don't clean up yet (body method will clean up)
        return notificationData["title"] as? String
    }

    /// Gets decoded body from stored content if available
    private func getDecodedBody(appGroupIdentifier: String) -> String? {
        guard let conversationId = notificationData?.protocolData?.conversationId else {
            return nil
        }

        let storageKey = "decoded_notification_\(conversationId)"

        guard let appGroupDefaults = UserDefaults(suiteName: appGroupIdentifier),
              let jsonString = appGroupDefaults.string(forKey: storageKey),
              let data = jsonString.data(using: .utf8),
              let notificationData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = notificationData["body"] as? String else {
            return nil
        }

        // Clean up the stored data after using it (since body is typically called after title)
        appGroupDefaults.removeObject(forKey: storageKey)

        return body
    }

        /// Checks if the notification has valid data for processing
    var isValid: Bool {
        return inboxId != nil && notificationType != nil
    }
}
