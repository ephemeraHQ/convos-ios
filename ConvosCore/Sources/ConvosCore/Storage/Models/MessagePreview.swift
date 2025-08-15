import Foundation

// MARK: - MessagePreview

struct MessagePreview: Codable, Equatable, Hashable {
    let text: String
    let createdAt: Date
}
