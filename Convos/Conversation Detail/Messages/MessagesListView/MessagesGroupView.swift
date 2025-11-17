import ConvosCore
import SwiftUI

struct MessagesGroupView: View {
    let group: MessagesGroup
    let isLastGroupByCurrentUser: Bool
    let onTapMessage: (AnyMessage) -> Void
    let onTapAvatar: (AnyMessage) -> Void

    var body: some View {
        HStack(spacing: DesignConstants.Spacing.step2x) {
            VStack {
                Spacer()

                if !group.sender.isCurrentUser {
                    ProfileAvatarView(profile: group.sender.profile, profileImage: nil)
                        .frame(width: DesignConstants.ImageSizes.smallAvatar,
                               height: DesignConstants.ImageSizes.smallAvatar)
                        .onTapGesture {
                            if let message = group.messages.last {
                                onTapAvatar(message)
                            }
                        }
                        .hoverEffect(.lift)
                        .id("profile-\(group.id)")
                }
            }
            .id("profile-container-\(group.id)")
            .transition(
                .asymmetric(
                    insertion: .identity,      // no transition on insert
                    removal: .identity
                )
            )

            VStack(alignment: .leading, spacing: DesignConstants.Spacing.stepX) {
                // Render published messages
                let allMessages = group.allMessages
                ForEach(Array(allMessages.enumerated()), id: \.element.base.id) { index, message in
                    if index == 0 && !group.sender.isCurrentUser {
                        // Show sender name for incoming messages
                        Text(group.sender.profile.displayName)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.leading, DesignConstants.Spacing.step2x)
                            .padding(.bottom, DesignConstants.Spacing.stepHalf)
                    }

                    let isLastPublished = message == group.messages.last
                    let isLast = message == group.unpublished.last || isLastPublished
                    let bubbleType: MessagesCollectionCell.BubbleType = isLast ? .tailed : .normal

                    MessagesGroupItemView(
                        message: message,
                        bubbleType: bubbleType,
                        showsSentStatus: isLastPublished && isLastGroupByCurrentUser,
                        onTapMessage: onTapMessage,
                        onTapAvatar: onTapAvatar
                    )
                    .transition(
                        .asymmetric(
                            insertion: .identity,      // no transition on insert
                            removal: .opacity
                        )
                    )
                }
            }
            .transition(
                .asymmetric(
                    insertion: .identity,      // no transition on insert
                    removal: .opacity
                )
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: group.messages)
        }
        .padding(.vertical, DesignConstants.Spacing.stepX)
        .id(group.id)
    }
}

#Preview("Incoming Messages") {
    ScrollView {
        MessagesGroupView(
            group: .mockIncoming,
            isLastGroupByCurrentUser: false,
            onTapMessage: { _ in },
            onTapAvatar: { _ in }
        )
        .padding()
    }
    .background(.colorBackgroundPrimary)
}

#Preview("Outgoing Messages") {
    ScrollView {
        MessagesGroupView(
            group: .mockOutgoing,
            isLastGroupByCurrentUser: true,
            onTapMessage: { _ in },
            onTapAvatar: { _ in }
        )
        .padding()
    }
    .background(.colorBackgroundPrimary)
}

#Preview("Mixed Published/Unpublished") {
    ScrollView {
        MessagesGroupView(
            group: .mockMixed,
            isLastGroupByCurrentUser: true,
            onTapMessage: { _ in },
            onTapAvatar: { _ in }
        )
        .padding()
    }
    .background(.colorBackgroundPrimary)
}
