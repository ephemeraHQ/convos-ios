import Combine
import Foundation
import SwiftUI

@Observable
class MessageReactionMenuViewModel {
    private(set) var isCollapsed: Bool = false {
        didSet {
            _isCollapsedPublisher.send(isCollapsed)
        }
    }

    private let _isCollapsedPublisher: PassthroughSubject<Bool, Never> = .init()
    var isCollapsedPublisher: AnyPublisher<Bool, Never> {
        _isCollapsedPublisher.eraseToAnyPublisher()
    }

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

    func toggleCollapsed() {
        isCollapsed.toggle()
    }
}
