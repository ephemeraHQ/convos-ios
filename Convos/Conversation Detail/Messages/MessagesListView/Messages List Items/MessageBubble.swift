import ConvosCore
import SwiftUI

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
                EmptyView()
                //                Group {
//                    if isOutgoing {
//                        EmptyView()
//                    } else {
//                        if style == .normal {
//                            Spacer()
//                        } else {
//                            ProfileAvatarView(profile: profile, profileImage: nil)
//                        }
//                    }
//                }
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
