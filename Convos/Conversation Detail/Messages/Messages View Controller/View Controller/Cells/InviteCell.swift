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
                if let inviteURL = invite.inviteURL {
                    QRCodeView(url: inviteURL, backgroundColor: .colorFillMinimal)
                        .frame(maxWidth: 220, maxHeight: 220)
                        .padding(DesignConstants.Spacing.step12x)
                }
            }
            .background(.colorFillMinimal)
            .mask(RoundedRectangle(cornerRadius: 38.0))

            #if DEBUG
            Text(invite.code)
                .frame(maxWidth: 180.0)
                .lineLimit(0)
                .multilineTextAlignment(.center)
                .font(.system(size: 10.0))
                .kerning(1.0)
                .foregroundStyle(.colorTextSecondary)
            #endif
        }
    }
}

#Preview {
    InviteView(invite: .mock())
}
