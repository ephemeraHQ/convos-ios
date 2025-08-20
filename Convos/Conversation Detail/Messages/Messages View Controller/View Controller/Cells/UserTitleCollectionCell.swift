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

struct UserTitleView: View {
    let name: String
    let source: MessageSource
    var body: some View {
        if !name.isEmpty {
            HStack {
                if source == .outgoing {
                    Spacer()
                }
                Text(name)
                    .lineLimit(1)
                    .font(.caption2)
                    .foregroundStyle(Color.gray)
                    .truncationMode(.tail)
                if source == .incoming {
                    Spacer()
                }
            }
        } else {
            EmptyView()
        }
    }
}

#Preview {
    let cell = UserTitleCollectionCell()
    cell.setup(name: "John Doe", source: .outgoing)
    return cell
}

#Preview {
    let cell = UserTitleCollectionCell()
    cell.setup(name: "John Doe", source: .incoming)
    return cell
}
