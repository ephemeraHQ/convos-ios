import ConvosCore
import UIKit

// swiftlint:disable force_cast

final class CellFactory {
    static func createCell(in collectionView: UICollectionView,
                           for indexPath: IndexPath,
                           with item: MessagesCollectionCell,
                           onTapAvatar: @escaping () -> Void) -> UICollectionViewCell {
        switch item {
        case let .message(message):
            return createMessagesCell(in: collectionView, for: indexPath, message: message, onTapAvatar: onTapAvatar)
        case .typingIndicator:
            return createTypingIndicatorCell(in: collectionView, for: indexPath)
        }
    }

    private static func createMessagesCell(in collectionView: UICollectionView,
                                           for indexPath: IndexPath,
                                           message: MessagesListItemType,
                                           onTapAvatar: @escaping () -> Void) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MessagesListItemTypeCell.reuseIdentifier,
                                                      for: indexPath) as! MessagesListItemTypeCell
        cell.setup(item: message, onTapAvatar: onTapAvatar)
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
}

// swiftlint:enable force_cast
