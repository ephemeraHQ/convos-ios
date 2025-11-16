import ConvosCore
import SwiftUI

struct MessageTransitionModifier: ViewModifier {
    let source: MessageSource
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive ? 0.9 : 1.0)
            .rotationEffect(
                isActive
                ? .radians(source == .incoming ? -0.05 : 0.05)
                : .radians(0)
            )
            .offset(
                x: isActive
                ? (source == .incoming ? -20 : 20)
                : 0,
                y: isActive ? 40 : 0
            )
    }
}

extension AnyTransition {
    static func message(source: MessageSource) -> AnyTransition {
        .modifier(
            active: MessageTransitionModifier(source: source, isActive: true),
            identity: MessageTransitionModifier(source: source, isActive: false)
        )
    }
}

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
                        .id(group.sender.id)
                }
            }

            VStack(alignment: .leading, spacing: DesignConstants.Spacing.stepX) {
                // Render published messages
                ForEach(Array(group.messages.enumerated()), id: \.element.base.id) { index, message in
                    if index == 0 && !group.sender.isCurrentUser {
                        // Show sender name for incoming messages
                        Text(group.sender.profile.displayName)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.leading, DesignConstants.Spacing.step2x)
                            .padding(.bottom, DesignConstants.Spacing.stepHalf)
                    }
                    let isLast = index == group.messages.count - 1
                    let bubbleType: MessagesCollectionCell.BubbleType = isLast ? .tailed : .normal

                    renderMessage(
                        message,
                        bubbleType: bubbleType
                    )
                }

                // Show "Sent" indicator for last group by current user
                if isLastGroupByCurrentUser && !group.messages.isEmpty {
                    HStack {
                        Spacer()
                        Text("Sent")
                            .font(.footnote)
                            .foregroundStyle(.colorTextSecondary)
                            .padding(.bottom, DesignConstants.Spacing.stepHalf)
                        Image(systemName: "checkmark")
                            .font(.footnote)
                            .foregroundStyle(.colorTextSecondary)
                    }
                    .zIndex(100)
                }

                // Render unpublished messages
                ForEach(Array(group.unpublished.enumerated()), id: \.element.base.id) { index, message in
                    let isLast = index == group.unpublished.count - 1
                    let bubbleType: MessagesCollectionCell.BubbleType = isLast ? .tailed : .normal
                    renderMessage(
                        message,
                        bubbleType: bubbleType
                    )
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: group)
        }
        .id(group.id)
    }

    @ViewBuilder
    private func renderMessage(_ message: AnyMessage, bubbleType: MessagesCollectionCell.BubbleType) -> some View {
        let isPublished = message.base.status == .published

        switch message.base.content {
        case .text(let text), .emoji(let text):
            MessageBubble(
                style: bubbleType,
                message: text,
                isOutgoing: message.base.sender.isCurrentUser,
                profile: message.base.sender.profile,
                onTapAvatar: { onTapAvatar(message) }
            )
            .zIndex(200)
            .id(message.base.id)
//            .opacity(isPublished ? 1.0 : 0.6)  // Visual indication for unpublished messages
            .onTapGesture {
                onTapMessage(message)
            }
            .transition(
                .asymmetric(
                    insertion: .message(source: message.base.source),
                    removal: .identity
                )
            )


        case .attachment(let url):
            // TODO: Implement attachment view
            EmptyView()

        case .attachments(let urls):
            // TODO: Implement attachments view
            EmptyView()

        case .update:
            // Updates are handled at the item level, not here
            EmptyView()
        }
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
