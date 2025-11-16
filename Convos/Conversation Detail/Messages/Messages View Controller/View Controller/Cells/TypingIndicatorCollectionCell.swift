import SwiftUI
import UIKit

class TypingIndicatorCollectionCell: UICollectionViewCell {
    func prepare(with alignment: MessagesCollectionCell.Alignment) {
        contentConfiguration = UIHostingConfiguration {
            HStack {
                TypingIndicatorView(alignment: alignment)
                Spacer()
            }
        }
    }
}
