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
                                          message: Message,
                                          bubbleType: MessagesCollectionCell.BubbleType) -> UICollectionViewCell {
        switch message.kind {
        case let .text(text):
            return createTextCell(
                in: collectionView,
                for: indexPath,
                text: text,
                bubbleType: bubbleType,
                messageType: message.source
            )
        case let .attachment(imageURL):
            return createImageCell(
                in: collectionView,
                messageId: message.id,
                for: indexPath,
                profile: message.userProfile,
                source: .imageURL(imageURL),
                messageType: message.source
            )
        }
    }

    private static func createTextCell(
        in collectionView: UICollectionView,
        for indexPath: IndexPath,
        text: String,
        bubbleType: MessagesCollectionCell.BubbleType,
        messageType: Message.Source
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
        messageType: Message.Source
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
