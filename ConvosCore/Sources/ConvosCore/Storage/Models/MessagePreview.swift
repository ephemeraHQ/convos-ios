import Foundation

// MARK: - MessagePreview

public struct MessagePreview: Codable, Equatable, Hashable, Sendable {
    public let text: String
    public let createdAt: Date
}
