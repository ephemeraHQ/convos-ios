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

struct TypingIndicatorView: View {
    let alignment: MessagesCollectionCell.Alignment
    var body: some View {
        MessageContainer(style: .tailed,
                         isOutgoing: false) {
            ZStack {
                Text("")
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12.0)
                    .font(.body)
                PulsingCircleView.typingIndicator
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        } avatarView: {
            Spacer()
        }
    }
}

#Preview {
    TypingIndicatorView(alignment: .leading)
}
