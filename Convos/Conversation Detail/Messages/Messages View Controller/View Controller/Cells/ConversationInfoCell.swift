import ConvosCore
import SwiftUI
import UIKit

class ConversationInfoCell: UICollectionViewCell {
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

    func setup(conversation: Conversation) {
        contentConfiguration = UIHostingConfiguration {
            VStack(alignment: .leading) {
                ConversationInfoPreview(conversation: conversation)
                    .frame(maxWidth: 320.0, alignment: .center)
                    .padding(.horizontal, DesignConstants.Spacing.step6x)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .id(conversation.id)
        }
        .margins(.vertical, 0.0)
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        layoutAttributesForHorizontalFittingRequired(layoutAttributes)
    }
}
