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
