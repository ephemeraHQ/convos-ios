import SwiftUI
import UIKit

class InviteCell: UICollectionViewCell {
    func prepare(with invite: Invite, hasVerticalPadding: Bool) {
        contentConfiguration = UIHostingConfiguration {
            InviteView(invite: invite, hasVerticalPadding: hasVerticalPadding)
        }
    }
}

struct InviteView: View {
    let invite: Invite
    let hasVerticalPadding: Bool

    var body: some View {
        VStack {
            Group {
                QRCodeView(
                    identifier: invite.temporaryInviteString, // invite.inviteUrlString, @jarodl temporary
                    backgroundColor: .colorFillMinimal
                )
                .padding(DesignConstants.Spacing.step12x)
            }
            .background(.colorFillMinimal)
            .mask(RoundedRectangle(cornerRadius: 38.0))
            .padding(.vertical, hasVerticalPadding ? 136.0 : 0.0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    InviteView(invite: .mock(), hasVerticalPadding: true)
}
