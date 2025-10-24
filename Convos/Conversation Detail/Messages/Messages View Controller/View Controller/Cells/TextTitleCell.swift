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

struct TextTitleContentView: View {
    let title: String
    let profile: Profile?

    var body: some View {
        HStack(spacing: DesignConstants.Spacing.step2x) {
            if let profile {
                ProfileAvatarView(profile: profile, profileImage: nil)
                    .frame(width: 16.0, height: 16.0)
            }

            Text(title)
                .lineLimit(1)
                .font(.caption2)
                .foregroundStyle(.colorTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

#Preview {
    let cell = TextTitleCell()
    cell.setup(title: "Sample Title", profile: .mock())
    return cell
}

#Preview {
    let cell = TextTitleCell()
    cell.setup(title: "A Much Longer Title That Should Be Centered", profile: .mock())
    return cell
}
