import UIKit
import SwiftUI

class TextMessageCollectionCell: UICollectionViewCell {

    override func prepareForReuse() {
        super.prepareForReuse()
        self.contentConfiguration = nil
    }

    func setup(message: String, messageType: MessageType, style: Cell.BubbleType) {
        contentConfiguration = UIHostingConfiguration {
            VStack(alignment: .leading) {
                MessageBubble(style: style,
                              message: message,
                              isOutgoing: messageType == .outgoing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
//        .margins(.top, messageType == .outgoing ? 8.0 : 0.0)
        .margins(.top, 0.0)
        .margins(.bottom, 0.0)
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        layoutAttributesForHorizontalFittingRequired(layoutAttributes)
    }
}

struct MessageBubble: View {
    let style: Cell.BubbleType
    let message: String
    let isOutgoing: Bool

    var body: some View {
        HStack {
            MessageContainer(style: style,
                             isOutgoing: isOutgoing) {
                Text(message)
                    .foregroundColor(isOutgoing ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

            }
        }
    }
}

#Preview {
    VStack {
        ForEach([MessageType.outgoing, MessageType.incoming], id: \.self) { type in
            MessageBubble(style: .normal,
                message: "Hello world!", isOutgoing: type == .outgoing)
        }
    }
}
