import ConvosCore
import SwiftUI
import UIKit

class MessagesListItemTypeCell: UICollectionViewCell {
    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.contentConfiguration = nil
    }

    func setup(
        item: MessagesListItemType,
        onTapAvatar: (() -> Void)?
    ) {
        contentConfiguration = UIHostingConfiguration {
            Group {
                switch item {
                case .date(let dateGroup):
                    TextTitleContentView(title: dateGroup.value, profile: nil)
                        .id(dateGroup.differenceIdentifier)
                        .padding(.vertical, DesignConstants.Spacing.step4x)

                case .update(_, let update, _):
                    TextTitleContentView(title: update.summary, profile: update.profile)
                        .id(update.differenceIdentifier)
                        .padding(.vertical, DesignConstants.Spacing.step4x)

                case .messages(let group):
                    MessagesGroupView(
                        group: group,
                        onTapMessage: { _ in },
                        onTapAvatar: { _ in },
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id("message-cell-\(item.differenceIdentifier)")
        }
        .margins(.horizontal, 0.0)
        .margins(.vertical, 0.0)
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        layoutAttributesForHorizontalFittingRequired(layoutAttributes)
    }
}
