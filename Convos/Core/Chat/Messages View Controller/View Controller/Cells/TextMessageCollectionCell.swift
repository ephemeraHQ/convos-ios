import SwiftUI
import UIKit

class TextMessageCollectionCell: UICollectionViewCell {
    private var message: String = ""
    private var messageType: Message.Source = .incoming
    private var bubbleStyle: MessagesCollectionCell.BubbleType = .normal
    private var longPressGestureRecognizer: UILongPressGestureRecognizer?
    private var panGestureRecognizer: UIPanGestureRecognizer?
    private var doubleTapGestureRecognizer: UITapGestureRecognizer?

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.contentConfiguration = nil
        message = ""
        messageType = .incoming
        bubbleStyle = .normal
    }

    func setup(message: String, messageType: Message.Source, style: MessagesCollectionCell.BubbleType) {
        self.message = message
        self.messageType = messageType
        self.bubbleStyle = style
        contentConfiguration = UIHostingConfiguration {
            VStack(alignment: .leading) {
                MessageBubble(
                    style: style,
                    message: message,
                    isOutgoing: messageType == .outgoing
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .margins(.vertical, 0.0)
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        layoutAttributesForHorizontalFittingRequired(layoutAttributes)
    }
}

extension TextMessageCollectionCell: PreviewableCell {
    var sourceCellEdge: MessageReactionMenuController.Configuration.Edge {
        messageType == .incoming ? .leading : .trailing
    }
}

struct MessageBubble: View {
    let style: MessagesCollectionCell.BubbleType
    let message: String
    let isOutgoing: Bool
    var body: some View {
        HStack {
            MessageContainer(style: style, isOutgoing: isOutgoing) {
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
        ForEach([Message.Source.outgoing, Message.Source.incoming], id: \.self) { type in
            MessageBubble(style: .normal,
                          message: "Hello world!", isOutgoing: type == .outgoing)
        }
    }
}
