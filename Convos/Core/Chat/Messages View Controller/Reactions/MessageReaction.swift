import Foundation

struct MessageReaction: Identifiable {
    var id: String {
        emoji
    }
    let emoji: String
    let isSelected: Bool
}

