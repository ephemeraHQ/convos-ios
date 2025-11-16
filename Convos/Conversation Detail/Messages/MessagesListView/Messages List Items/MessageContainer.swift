import SwiftUI

struct MessageContainer<Content: View, AvatarView: View>: View {
    let style: MessagesCollectionCell.BubbleType
    let isOutgoing: Bool
    let cornerRadius: CGFloat = Constant.bubbleCornerRadius
    let content: () -> Content
    let avatarView: () -> AvatarView
    let onTapAvatar: (() -> Void)?

    var spacer: some View {
        Group {
            Spacer()
            Spacer()
                .frame(maxWidth: 50.0)
        }
    }

    var mask: UnevenRoundedRectangle {
        switch style {
        case .normal:
            return .rect(
                topLeadingRadius: cornerRadius,
                bottomLeadingRadius: cornerRadius,
                bottomTrailingRadius: cornerRadius,
                topTrailingRadius: cornerRadius
            )
        case .tailed:
            if isOutgoing {
                return .rect(
                    topLeadingRadius: cornerRadius,
                    bottomLeadingRadius: cornerRadius,
                    bottomTrailingRadius: 2.0,
                    topTrailingRadius: cornerRadius
                )
            } else {
                return .rect(
                    topLeadingRadius: cornerRadius,
                    bottomLeadingRadius: 2.0,
                    bottomTrailingRadius: cornerRadius,
                    topTrailingRadius: cornerRadius
                )
            }
        }
    }

    var avatar: some View {
        avatarView()
            .frame(width: DesignConstants.ImageSizes.smallAvatar,
                   height: DesignConstants.ImageSizes.smallAvatar)
            .onTapGesture {
                onTapAvatar?()
            }
            .hoverEffect(.lift)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0.0) {
            if isOutgoing {
                spacer
            } else {
                avatar
                    .padding(.trailing, DesignConstants.Spacing.step2x)
            }

            content()
                .background(isOutgoing ? Color.colorBubble : Color.colorBubbleIncoming)
                .foregroundColor(isOutgoing ? .colorTextPrimaryInverted : .colorTextPrimary)
                .mask(mask)

            if !isOutgoing {
                spacer
            } else {
                avatar
                    .padding(.leading, DesignConstants.Spacing.step2x)
            }
        }
    }
}
