import UIKit

// swiftlint:disable force_cast

final class CellFactory {
    static func createCell(in collectionView: UICollectionView,
                           for indexPath: IndexPath,
                           with item: MessagesCollectionCell) -> UICollectionViewCell {
        switch item {
        case let .message(message, bubbleType: bubbleType):
            return createMessageCell(in: collectionView, for: indexPath, message: message, bubbleType: bubbleType)
        case let .messageGroup(group):
            return createGroupTitle(in: collectionView, for: indexPath, title: group.title)
        case let .date(group):
            return createDateTitle(in: collectionView, for: indexPath, title: group.value)
        case .typingIndicator:
            return createTypingIndicatorCell(in: collectionView, for: indexPath)
        }
    }

    private static func createMessageCell(in collectionView: UICollectionView,
                                          for indexPath: IndexPath,
                                          message: AnyMessage,
                                          bubbleType: MessagesCollectionCell.BubbleType) -> UICollectionViewCell {
        switch message {
        case .message(let message):
            switch message.content {
            case .update(let update):
                return createConversationUpdate(in: collectionView, for: indexPath, update: update)
            case .text(let string), .emoji(let string):
                return createTextCell(
                    in: collectionView,
                    for: indexPath,
                    text: string,
                    bubbleType: bubbleType,
                    messageType: message.source
                )
            case .attachment(let attachmentURL):
                return createImageCell(
                    in: collectionView,
                    messageId: message.id,
                    for: indexPath,
                    profile: message.sender,
                    source: .imageURL(attachmentURL),
                    messageType: message.source
                )
            case .attachments:
                return UICollectionViewCell()
            }
        case .reply(let reply):
            switch reply.content {
            case .text(let string), .emoji(let string):
                return createTextCell(
                    in: collectionView,
                    for: indexPath,
                    text: string,
                    bubbleType: bubbleType,
                    messageType: reply.source
                )
            case .attachment(let attachmentURL):
                return createImageCell(
                    in: collectionView,
                    messageId: reply.id,
                    for: indexPath,
                    profile: reply.sender,
                    source: .imageURL(attachmentURL),
                    messageType: reply.source
                )
            case .attachments, .update:
                return UICollectionViewCell()
            }
        }
    }

    private static func createTextCell(
        in collectionView: UICollectionView,
        for indexPath: IndexPath,
        text: String,
        bubbleType: MessagesCollectionCell.BubbleType,
        messageType: MessageSource
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TextMessageCollectionCell.reuseIdentifier,
                                                      for: indexPath) as! TextMessageCollectionCell
        cell.setup(message: text, messageType: messageType, style: bubbleType)
        return cell
    }

    private static func createImageCell(
        in collectionView: UICollectionView,
        messageId: String,
        for indexPath: IndexPath,
        profile: Profile,
        source: ImageSource,
        messageType: MessageSource
    ) -> ImageCollectionCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ImageCollectionCell.reuseIdentifier,
            for: indexPath
        ) as! ImageCollectionCell
        cell.setup(with: source, messageType: messageType)
        cell.layoutMargins = .init(top: 0.0, left: 8.0, bottom: 0.0, right: 8.0)
        return cell
    }

    private static func createTypingIndicatorCell(in collectionView: UICollectionView,
                                                  for indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: TypingIndicatorCollectionCell.reuseIdentifier,
            for: indexPath
        ) as! TypingIndicatorCollectionCell
        cell.prepare(with: .leading)
        return cell
    }

    private static func createGroupTitle(in collectionView: UICollectionView,
                                         for indexPath: IndexPath,
                                         title: String) -> UserTitleCollectionCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: UserTitleCollectionCell.reuseIdentifier,
            for: indexPath
        ) as! UserTitleCollectionCell
        cell.setup(name: title)
        return cell
    }

    private static func createConversationUpdate(in collectionView: UICollectionView,
                                                 for indexPath: IndexPath,
                                                 update: ConversationUpdate) -> TextTitleCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: TextTitleCell.reuseIdentifier,
            for: indexPath
        ) as! TextTitleCell
        cell.setup(title: update.summary)
        return cell
    }

    private static func createDateTitle(in collectionView: UICollectionView,
                                        for indexPath: IndexPath,
                                        title: String) -> TextTitleCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: TextTitleCell.reuseIdentifier,
            for: indexPath
        ) as! TextTitleCell
        cell.setup(title: title)
        return cell
    }
}

// swiftlint:enable force_cast
