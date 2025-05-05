import DifferenceKit
import Foundation
import UIKit

enum Cell: Hashable {
    enum Alignment {
        case leading, center, trailing, fullWidth
    }

    enum BubbleType {
        case normal, tailed
    }

    case message(Message, bubbleType: BubbleType)
    case typingIndicator
    case messageGroup(MessageGroup)
    case date(DateGroup)

    var alignment: Cell.Alignment {
        switch self {
        case let .message(message, _):
            message.type == .incoming ? .leading : .trailing
        case .typingIndicator:
            .leading
        case let .messageGroup(group):
            group.type == .incoming ? .leading : .trailing
        case .date:
            .center
        }
    }
}

extension Cell: Differentiable {
    var differenceIdentifier: Int {
        switch self {
        case let .message(message, _):
            message.differenceIdentifier
        case .typingIndicator:
            hashValue
        case let .messageGroup(group):
            group.differenceIdentifier
        case let .date(group):
            group.differenceIdentifier
        }
    }

    func isContentEqual(to source: Cell) -> Bool {
        self == source
    }
}
