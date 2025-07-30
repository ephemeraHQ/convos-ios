import SwiftUI
import UIKit

class InviteCell: UICollectionViewCell {
    override func prepareForReuse() {
        super.prepareForReuse()
        contentConfiguration = nil
    }

    func prepare(with invite: Invite) {
        contentConfiguration = UIHostingConfiguration {
            InviteView(invite: invite)
        }
        .margins(.vertical, 0.0)
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        let targetSize = CGSize(width: layoutAttributes.size.width,
                                height: layoutAttributes.size.width)
        layoutAttributes.size.height = targetSize.height
        return layoutAttributes
    }
}

struct InviteView: View {
    let invite: Invite

    var body: some View {
        VStack {
            Group {
                QRCodeView(
                    identifier: invite.temporaryInviteString, // invite.inviteUrlString, @jarodl temporary
                    backgroundColor: .colorFillMinimal
                )
                .frame(maxWidth: 220, maxHeight: 220)
                .padding(DesignConstants.Spacing.step12x)
            }
            .background(.colorFillMinimal)
            .mask(RoundedRectangle(cornerRadius: 38.0))
        }
    }
}

#Preview {
    InviteView(invite: .mock())
}
