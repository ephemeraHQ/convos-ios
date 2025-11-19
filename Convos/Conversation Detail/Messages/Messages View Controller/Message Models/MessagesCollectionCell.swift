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
    case messageGroup(MessageGroup)
    case date(DateGroup)
    case invite(Invite)
    case conversationInfo(Conversation)

    var alignment: MessagesCollectionCell.Alignment {
        switch self {
        case let .message(message):
                .center
//            switch message.base.content {
//            case .update:
//                .center
//            default:
//                message.base.source == .incoming ? .leading : .trailing
//            }
        case .typingIndicator:
            .leading
        case let .messageGroup(group):
            group.source == .incoming ? .leading : .trailing
        case .date, .invite, .conversationInfo:
            .center
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
        case let .messageGroup(group):
            group.differenceIdentifier
        case let .date(group):
            group.differenceIdentifier
        case let .invite(invite):
            invite.differenceIdentifier
        case let .conversationInfo(conversation):
            conversation.id.hashValue
        }
    }

    func isContentEqual(to source: MessagesCollectionCell) -> Bool {
        self == source
    }
}
