import Combine
import Foundation
import SwiftUI

@Observable
class MessageReactionMenuViewModel {
    var isCollapsed: Bool = false {
        didSet {
            updateShowingEmojiPicker()
            _isCollapsedPublisher.send(isCollapsed)
        }
    }

    var showingEmojiPicker: Bool = false

    private let _isCollapsedPublisher: PassthroughSubject<Bool, Never> = .init()
    var isCollapsedPublisher: AnyPublisher<Bool, Never> {
        _isCollapsedPublisher.eraseToAnyPublisher()
    }

    var selectedEmoji: String? {
        didSet {
            updateShowingEmojiPicker()
            _selectedEmojiPublisher.send(selectedEmoji)
        }
    }

    private let _selectedEmojiPublisher: PassthroughSubject<String?, Never> = .init()
    var selectedEmojiPublisher: AnyPublisher<String?, Never> {
        _selectedEmojiPublisher.eraseToAnyPublisher()
    }

    var reactions: [MessageReactionChoice] = [
        .init(emoji: "❤️", isSelected: false),
        .init(emoji: "👍", isSelected: false),
        .init(emoji: "👎", isSelected: false),
        .init(emoji: "😂", isSelected: false),
        .init(emoji: "😮", isSelected: false),
        .init(emoji: "🤔", isSelected: false),
    ]

    private func updateShowingEmojiPicker() {
        showingEmojiPicker = isCollapsed && selectedEmoji == nil
    }

    func add(reaction: MessageReactionChoice) {
        selectedEmoji = reaction.emoji
    }

    func showMoreReactions() {
    }

    func toggleCollapsed() {
        isCollapsed.toggle()
    }
}
