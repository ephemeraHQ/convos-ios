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

struct MessageBubble: View {
    let style: MessagesCollectionCell.BubbleType
    let message: String
    let isOutgoing: Bool
    let profile: Profile
    let onTapAvatar: (() -> Void)?

    private var textColor: Color {
        // Match the text color based on message type (same as MessageContainer)
        if isOutgoing {
            return Color.colorTextPrimaryInverted
        } else {
            return Color.colorTextPrimary
        }
    }

    var body: some View {
        HStack {
            MessageContainer(style: style, isOutgoing: isOutgoing) {
                LinkDetectingTextView(message, linkColor: textColor)
                    .foregroundStyle(textColor)
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
                            ProfileAvatarView(profile: profile, profileImage: nil)
                        }
                    }
                }
            } onTapAvatar: {
                onTapAvatar?()
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
                profile: .mock(),
                onTapAvatar: nil
            )
            MessageBubble(
                style: .normal,
                message: "Check out https://convos.org for more info",
                isOutgoing: type == .outgoing,
                profile: .mock(),
                onTapAvatar: nil
            )
            MessageBubble(
                style: .tailed,
                message: "Visit www.example.com or email us at hello@example.com",
                isOutgoing: type == .outgoing,
                profile: .mock(),
                onTapAvatar: nil
            )
        }
    }
    .padding(.horizontal, 12.0)
}
