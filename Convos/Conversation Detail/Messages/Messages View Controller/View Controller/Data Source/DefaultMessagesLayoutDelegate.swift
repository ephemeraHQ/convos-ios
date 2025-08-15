import ConvosCore
import UIKit

final class DefaultMessagesLayoutDelegate: MessagesLayoutDelegate {
    let sections: [MessagesCollectionSection]
    private let oldSections: [MessagesCollectionSection]

    init(sections: [MessagesCollectionSection], oldSections: [MessagesCollectionSection]) {
        self.sections = sections
        self.oldSections = oldSections
    }

    func shouldPresentHeader(_ messagesLayout: MessagesCollectionLayout, at sectionIndex: Int) -> Bool {
        true
    }

    func shouldPresentFooter(_ messagesLayout: MessagesCollectionLayout, at sectionIndex: Int) -> Bool {
        true
    }

    func sizeForItem(_ messagesLayout: MessagesCollectionLayout,
                     of kind: ItemKind,
                     at indexPath: IndexPath) -> ItemSize {
        switch kind {
        case .cell:
            let item = sections[indexPath.section].cells[indexPath.item]
            switch item {
            case let .message(message, bubbleType: _):
                switch message.base.content {
                case .text, .emoji:
                    return .estimated(CGSize(width: messagesLayout.layoutFrame.width, height: 36))
                case .attachment, .attachments:
                    return .estimated(CGSize(width: messagesLayout.layoutFrame.width, height: 120.0))
                case .update:
                    return .estimated(CGSize(width: messagesLayout.layoutFrame.width, height: 18))
                }
            case .date:
                return .estimated(CGSize(width: messagesLayout.layoutFrame.width, height: 18))
            case .invite:
                return .estimated(
                    CGSize(
                        width: messagesLayout.layoutFrame.width,
                        height: 316.0
                    )
                )
            case .typingIndicator:
                return .estimated(CGSize(width: 60, height: 36))
            case .messageGroup:
                return .estimated(CGSize(width: messagesLayout.layoutFrame.width, height: 18))
            }
        case .footer, .header:
            return .auto
        }
    }

    func alignmentForItem(_ messagesLayout: MessagesCollectionLayout,
                          of kind: ItemKind,
                          at indexPath: IndexPath) -> MessagesCollectionCell.Alignment {
        switch kind {
        case .header:
            return .center
        case .cell:
            let item = sections[indexPath.section].cells[indexPath.item]
            switch item {
            case .date, .invite:
                return .center
            case .message(let message, _):
                switch message.base.content {
                case .update:
                    return .center
                default:
                    return .fullWidth
                }
            case .messageGroup:
                return .fullWidth
            case .typingIndicator:
                return .leading
            }
        case .footer:
            return .trailing
        }
    }

    func initialLayoutAttributesForInsertedItem(_ messagesLayout: MessagesCollectionLayout,
                                                of kind: ItemKind,
                                                at indexPath: IndexPath,
                                                modifying originalAttributes: MessagesLayoutAttributes,
                                                on state: InitialAttributesRequestType) {
        originalAttributes.alpha = 0
        guard state == .invalidation,
              kind == .cell else {
            return
        }

        let item = sections[indexPath.section].cells[indexPath.item]
        switch item {
        case .messageGroup, .date:
            originalAttributes.center.y += originalAttributes.frame.height
        case let .message(message, bubbleType: _):
            switch message.base.content {
            case .text, .attachment, .attachments, .emoji:
                applyMessageAnimation(for: message, to: originalAttributes)
            default:
                break
            }
        case .typingIndicator:
            applyTypingIndicatorAnimation(to: originalAttributes)
        default:
            break
        }
    }

    func finalLayoutAttributesForDeletedItem(_ messagesLayout: MessagesCollectionLayout,
                                             of kind: ItemKind,
                                             at indexPath: IndexPath,
                                             modifying originalAttributes: MessagesLayoutAttributes) {
        originalAttributes.alpha = 0
        guard kind == .cell else {
            return
        }

        let oldItem = oldSections[indexPath.section].cells[indexPath.item]
        switch oldItem {
        case .messageGroup, .date:
            originalAttributes.center.y += originalAttributes.frame.height
        case let .message(message, bubbleType: _):
            switch message.base.content {
            case .text, .attachment, .attachments, .emoji:
                applyMessageAnimation(for: message, to: originalAttributes)
            default:
                break
            }
        case .typingIndicator:
            applyTypingIndicatorAnimation(to: originalAttributes)
        default:
            break
        }
    }

    func interItemSpacing(_ messagesLayout: MessagesCollectionLayout,
                          of kind: ItemKind,
                          after indexPath: IndexPath) -> CGFloat? {
        let item = sections[indexPath.section].cells[indexPath.item]

        switch item {
        case .messageGroup:
            return 3.0
        case .message:
            return 2.0
        case .date:
            return 0.0
        case .invite:
            return 0.0
        default:
            return nil
        }
    }

    func interSectionSpacing(_ messagesLayout: MessagesCollectionLayout, after sectionIndex: Int) -> CGFloat? {
        return nil
    }

    // MARK: - Private Helpers

    private func applyMessageAnimation(for message: AnyMessage, to attributes: MessagesLayoutAttributes) {
        attributes.transform = .init(scaleX: 0.9, y: 0.9)
        attributes.transform = attributes
            .transform
            .concatenating(
                .init(rotationAngle: message.base.source == .incoming ? -0.05 : 0.05)
            )
        attributes.center.x += (message.base.source == .incoming ? -20 : 20)
        attributes.center.y += 40
    }

    private func applyTypingIndicatorAnimation(to attributes: MessagesLayoutAttributes) {
        attributes.transform = .init(scaleX: 0.1, y: 0.1)
        attributes.center.x -= attributes.bounds.width / 5
    }
}
