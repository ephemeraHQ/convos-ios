import Foundation

// MARK: - Notification Payload Models

struct NotificationPayload: Codable {
    let body: NotificationBody

    init(body: NotificationBody) {
        self.body = body
    }
}

struct NotificationBody: Codable {
    let encryptedMessage: String
    let contentTopic: String
    let ethAddress: String
    let installationId: String?

    init(encryptedMessage: String, contentTopic: String, ethAddress: String, installationId: String? = nil) {
        self.encryptedMessage = encryptedMessage
        self.contentTopic = contentTopic
        self.ethAddress = ethAddress
        self.installationId = installationId
    }
}

// MARK: - Notification Content Types

enum NotificationContentType: String, Codable {
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

struct ProcessedNotificationContent {
    let title: String
    let subtitle: String?
    let body: String
    let threadIdentifier: String
    let attachmentURL: URL?
    let userInfo: [AnyHashable: Any]

    init(
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