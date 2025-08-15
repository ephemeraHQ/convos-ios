import Foundation

// MARK: - MessagePreview

public struct MessagePreview: Codable, Equatable, Hashable {
    public let text: String
    public let createdAt: Date
}
