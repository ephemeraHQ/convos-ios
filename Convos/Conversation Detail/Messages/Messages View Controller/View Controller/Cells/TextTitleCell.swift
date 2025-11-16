import ConvosCore
import SwiftUI
import UIKit

class TextTitleCell: UICollectionViewCell {
    override func prepareForReuse() {
        super.prepareForReuse()
        self.contentConfiguration = nil
    }

    func setup(title: String, profile: Profile?) {
        contentConfiguration = UIHostingConfiguration {
            TextTitleContentView(title: title, profile: profile)
        }
        .margins(.horizontal, 8.0)
        .margins(.vertical, 16.0)
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        layoutAttributesForHorizontalFittingRequired(layoutAttributes)
    }
}
