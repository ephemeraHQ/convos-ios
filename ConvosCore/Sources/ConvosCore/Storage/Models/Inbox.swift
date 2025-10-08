import Foundation

public struct Inbox: Codable, Hashable, Identifiable {
    public var id: String { inboxId }
    public let inboxId: String
    public let clientId: String
    public let createdAt: Date

    public init(inboxId: String, clientId: String, createdAt: Date = Date()) {
        self.inboxId = inboxId
        self.clientId = clientId
        self.createdAt = createdAt
    }
}

