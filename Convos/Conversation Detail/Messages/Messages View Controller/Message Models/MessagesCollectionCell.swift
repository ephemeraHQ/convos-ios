import ConvosCore
import DifferenceKit
import Foundation
import UIKit

enum MessagesCollectionCell: Hashable {
    enum Alignment {
        case leading, center, trailing, fullWidth
    }

    enum BubbleType {
        case normal, tailed, none
    }

    case message(MessagesListItemType)
    case typingIndicator

    var alignment: MessagesCollectionCell.Alignment {
        switch self {
        case .message:
            return .center
        case .typingIndicator:
            return .leading
        }
    }
}

extension MessagesListItemType: Differentiable {
    var differenceIdentifier: Int {
        id.hashValue
    }

    func isContentEqual(to source: MessagesListItemType) -> Bool {
        self.id == source.id
    }
}

extension MessagesCollectionCell: Differentiable {
    var differenceIdentifier: Int {
        switch self {
        case let .message(message):
            message.differenceIdentifier
        case .typingIndicator:
            hashValue
        }
    }

    func isContentEqual(to source: MessagesCollectionCell) -> Bool {
        self == source
    }
}
