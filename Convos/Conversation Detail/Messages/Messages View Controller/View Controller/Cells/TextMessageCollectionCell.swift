import ConvosCore
import SwiftUI
import UIKit

class TextMessageCollectionCell: UICollectionViewCell {
    private var messageType: MessageSource = .incoming
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
        messageType = .incoming
    }

    func setup(
        message: String,
        messageType: MessageSource,
        style: MessagesCollectionCell.BubbleType,
        profile: Profile,
        onTapAvatar: (() -> Void)?
    ) {
        self.messageType = messageType
        contentConfiguration = UIHostingConfiguration {
            VStack(alignment: .leading) {
                MessageBubble(
                    style: style,
                    message: message,
                    isOutgoing: messageType == .outgoing,
                    profile: profile,
                    onTapAvatar: onTapAvatar
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .margins(.top, DesignConstants.Spacing.stepX)
        .margins(.bottom, 0.0)
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
