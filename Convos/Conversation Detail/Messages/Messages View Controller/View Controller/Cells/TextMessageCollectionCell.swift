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
        profile: Profile
    ) {
        self.messageType = messageType
        contentConfiguration = UIHostingConfiguration {
            VStack(alignment: .leading) {
                MessageBubble(
                    style: style,
                    message: message,
                    isOutgoing: messageType == .outgoing,
                    profile: profile
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
    let profile: Profile
    var body: some View {
        HStack {
            MessageContainer(style: style, isOutgoing: isOutgoing) {
                Text(message)
                    .foregroundColor(isOutgoing ? .white : .primary)
                    .padding(.horizontal, DesignConstants.Spacing.step3x)
                    .padding(.vertical, DesignConstants.Spacing.step2x)
            } avatarView: {
                Group {
                    if isOutgoing {
                        EmptyView()
                    } else {
                        if style == .normal {
                            Spacer()
                        } else {
                            ProfileAvatarView(profile: profile)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    VStack {
        ForEach([MessageSource.outgoing, MessageSource.incoming], id: \.self) { type in
            MessageBubble(
                style: .normal,
                message: "Hello world!",
                isOutgoing: type == .outgoing,
                profile: .mock()
            )
            MessageBubble(
                style: .tailed,
                message: "Hello world!",
                isOutgoing: type == .outgoing,
                profile: .mock()
            )
        }
    }
    .padding(.horizontal, 12.0)
}
