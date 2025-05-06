import Foundation

class MessageReactionMenuViewModel: MessageReactionMenuViewModelType {
    var reactions: [MessageReaction] = [
        .init(id: "1", emoji: "❤️", isSelected: false),
        .init(id: "2", emoji: "👍", isSelected: false),
        .init(id: "3", emoji: "👎", isSelected: false),
        .init(id: "4", emoji: "😂", isSelected: false),
        .init(id: "5", emoji: "😮", isSelected: false),
        .init(id: "6", emoji: "🤔", isSelected: false),
    ]

    func add(reaction: MessageReaction) {
    }

    func showMoreReactions() {
    }
}
