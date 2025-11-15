import ConvosCore
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
}

struct InviteView: View {
    let invite: Invite

    var body: some View {
        VStack {
            Group {
                if !invite.isEmpty,
                   let inviteURL = invite.inviteURL {
                    QRCodeView(url: inviteURL, backgroundColor: .colorFillMinimal)
                        .frame(maxWidth: 220, maxHeight: 220)
                        .padding(DesignConstants.Spacing.step12x)
                } else {
                    EmptyView()
                        .frame(width: 220, height: 220.0)
                }
            }
            .transition(.blurReplace)
            .background(.colorFillMinimal)
            .mask(RoundedRectangle(cornerRadius: 38.0))
        }
    }
}

#Preview {
    InviteView(invite: .mock())
}
