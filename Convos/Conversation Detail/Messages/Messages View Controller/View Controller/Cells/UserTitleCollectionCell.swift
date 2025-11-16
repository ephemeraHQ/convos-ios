import ConvosCore
import SwiftUI
import UIKit

class UserTitleCollectionCell: UICollectionViewCell {
    override func prepareForReuse() {
        super.prepareForReuse()
        self.contentConfiguration = nil
    }

    func setup(name: String, source: MessageSource) {
        contentConfiguration = UIHostingConfiguration {
            UserTitleView(name: name, source: source)
        }
        .margins(.horizontal, 56.0)
        .margins(.top, DesignConstants.Spacing.step2x)
        .margins(.bottom, 0.0)
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        layoutAttributesForHorizontalFittingRequired(layoutAttributes)
    }
}
