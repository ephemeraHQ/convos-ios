import UIKit

final class DefaultMessagesLayout: MessagesLayoutDelegate {
    private let sections: [Section]
    private let oldSections: [Section]

    init(sections: [Section], oldSections: [Section] = []) {
        self.sections = sections
        self.oldSections = oldSections
    }

    func shouldPresentHeader(_ messagesLayout: MessagesCollectionLayout, at sectionIndex: Int) -> Bool {
        true
    }

    func shouldPresentFooter(_ messagesLayout: MessagesCollectionLayout, at sectionIndex: Int) -> Bool {
        true
    }

    func sizeForItem(_ messagesLayout: MessagesCollectionLayout, of kind: ItemKind, at indexPath: IndexPath) -> ItemSize {
        switch kind {
        case .cell:
            let item = sections[indexPath.section].cells[indexPath.item]
            switch item {
            case let .message(message, bubbleType: _):
                switch message.data {
                case .text:
                    return .estimated(CGSize(width: messagesLayout.layoutFrame.width, height: 36))
                case let .image(_, isLocallyStored: isDownloaded):
                    return .estimated(CGSize(width: messagesLayout.layoutFrame.width, height: isDownloaded ? 120 : 80))
                }
            case .date:
                return .estimated(CGSize(width: messagesLayout.layoutFrame.width, height: 18))
            case .typingIndicator:
                return .estimated(CGSize(width: 60, height: 36))
            case .messageGroup:
                return .estimated(CGSize(width: min(85, messagesLayout.layoutFrame.width / 3), height: 18))
            }
        case .footer, .header:
            return .auto
        }
    }

    func alignmentForItem(_ messagesLayout: MessagesCollectionLayout, of kind: ItemKind, at indexPath: IndexPath) -> Cell.Alignment {
        switch kind {
        case .header:
            return .center
        case .cell:
            let item = sections[indexPath.section].cells[indexPath.item]
            switch item {
            case .date:
                return .center
            case .message:
                return .fullWidth
            case .messageGroup, .typingIndicator:
                return .leading
            }
        case .footer:
            return .trailing
        }
    }

    func initialLayoutAttributesForInsertedItem(_ messagesLayout: MessagesCollectionLayout, of kind: ItemKind, at indexPath: IndexPath, modifying originalAttributes: MessagesLayoutAttributes, on state: InitialAttributesRequestType) {
        originalAttributes.alpha = 0
        guard state == .invalidation,
              kind == .cell else {
            return
        }

        switch sections[indexPath.section].cells[indexPath.item] {
        case .messageGroup:
            originalAttributes.alpha = 0.0
        case let .message(message, bubbleType: _):
            applyMessageAnimation(for: message, to: originalAttributes)
        case .typingIndicator:
            applyTypingIndicatorAnimation(to: originalAttributes)
        default:
            break
        }
    }

    func finalLayoutAttributesForDeletedItem(_ messagesLayout: MessagesCollectionLayout, of kind: ItemKind, at indexPath: IndexPath, modifying originalAttributes: MessagesLayoutAttributes) {
        originalAttributes.alpha = 0
        guard kind == .cell else {
            return
        }

        switch oldSections[indexPath.section].cells[indexPath.item] {
        case .messageGroup:
            originalAttributes.alpha = 0.0
        case let .message(message, bubbleType: _):
            applyMessageAnimation(for: message, to: originalAttributes)
        case .typingIndicator:
            applyTypingIndicatorAnimation(to: originalAttributes)
        default:
            break
        }
    }

    func interItemSpacing(_ messagesLayout: MessagesCollectionLayout, of kind: ItemKind, after indexPath: IndexPath) -> CGFloat? {
        let item = sections[indexPath.section].cells[indexPath.item]
        switch item {
        case .messageGroup:
            return 3.0
        case .message:
            return 2.0
        case .date:
            return 0.0
        default:
            return nil
        }
    }

    func interSectionSpacing(_ messagesLayout: MessagesCollectionLayout, after sectionIndex: Int) -> CGFloat? {
        return nil
    }

    // MARK: - Private Helpers

    private func applyMessageAnimation(for message: Message, to attributes: MessagesLayoutAttributes) {
        attributes.transform = .init(scaleX: 0.9, y: 0.9)
        attributes.transform = attributes.transform.concatenating(.init(rotationAngle: message.type == .incoming ? -0.05 : 0.05))
        attributes.center.x += (message.type == .incoming ? -20 : 20)
        attributes.center.y += 40
    }

    private func applyTypingIndicatorAnimation(to attributes: MessagesLayoutAttributes) {
        attributes.transform = .init(scaleX: 0.1, y: 0.1)
        attributes.center.x -= attributes.bounds.width / 5
    }
}
