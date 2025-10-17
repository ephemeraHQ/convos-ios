import Foundation

extension String {
    var xmtpGroupTopicFormat: String {
        "/xmtp/mls/1/g-\(self)/proto"
    }

    var xmtpWelcomeTopicFormat: String {
        "/xmtp/mls/1/w-\(self)/proto"
    }

    public var conversationIdFromXMTPGroupTopic: String? {
        // Example: /xmtp/mls/1/g-<conversationId>/proto -> <conversationId>
        let parts = split(separator: "/")
        guard let segment = parts.first(where: { $0.hasPrefix("g-") }) else {
            return nil
        }
        return String(segment.dropFirst(2))
    }
}
