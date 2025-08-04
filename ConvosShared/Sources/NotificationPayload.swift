import Foundation

// MARK: - Notification Payload Models

public struct NotificationPayload: Codable {
    public let body: NotificationBody

    public init(body: NotificationBody) {
        self.body = body
    }
}

public struct NotificationBody: Codable {
    public let encryptedMessage: String
    public let contentTopic: String
    public let ethAddress: String
    public let installationId: String?

    public init(encryptedMessage: String, contentTopic: String, ethAddress: String, installationId: String? = nil) {
        self.encryptedMessage = encryptedMessage
        self.contentTopic = contentTopic
        self.ethAddress = ethAddress
        self.installationId = installationId
    }
}

// MARK: - Notification Content Types

public enum NotificationContentType: String, Codable {
    case message
    case groupInvite = "group_invite"
    case reaction
    case mention
    case remoteAttachment = "remote_attachment"
    case multiRemoteAttachment = "multi_remote_attachment"
    case reply
    case unknown
}

// MARK: - Processed Notification Content

public struct ProcessedNotificationContent {
    public let title: String
    public let subtitle: String?
    public let body: String
    public let threadIdentifier: String
    public let attachmentURL: URL?
    public let userInfo: [AnyHashable: Any]

    public init(
        title: String,
        subtitle: String? = nil,
        body: String,
        threadIdentifier: String,
        attachmentURL: URL? = nil,
        userInfo: [AnyHashable: Any] = [:]
    ) {
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.threadIdentifier = threadIdentifier
        self.attachmentURL = attachmentURL
        self.userInfo = userInfo
    }
}
