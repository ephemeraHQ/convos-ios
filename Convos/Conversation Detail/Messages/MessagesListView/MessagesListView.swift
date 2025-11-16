import ConvosCore
import SwiftUI

struct MessagesListView: View {
    let conversation: Conversation
    @Binding var messages: [MessagesListItemType]
    let invite: Invite
    let onTapMessage: (AnyMessage) -> Void
    let onTapAvatar: (AnyMessage) -> Void
    let bottomBarHeight: CGFloat
    @State private var scrollPosition: ScrollPosition = ScrollPosition(edge: .bottom)

    var body: some View {
        ScrollViewReader { _ in
            ScrollView {
                LazyVStack(spacing: 0.0) {
                    // Show invite or conversation info at the top
                    if conversation.creator.isCurrentUser {
                        InviteView(invite: invite)
                            .id("invite")
                    } else {
                        ConversationInfoPreview(conversation: conversation)
                            .id("conversation-info")
                    }

                    // Render each message list item
                    ForEach(messages) { item in
                        Group {
                            switch item {
                            case .date(let dateGroup):
                                TextTitleContentView(title: dateGroup.value, profile: nil)
                                    .padding(.vertical, DesignConstants.Spacing.step2x)

                            case .update(_, let update):
                                TextTitleContentView(title: update.summary, profile: update.profile)
                                    .padding(.vertical, DesignConstants.Spacing.stepX)

                            case .messages(let group):
                                VStack(alignment: .leading, spacing: DesignConstants.Spacing.stepX) {
                                    // Combine all messages maintaining chronological order
                                    let allMessages = group.allMessages.sorted { $0.base.date < $1.base.date }

                                    // Render each message in the group
                                    ForEach(Array(group.messages.enumerated()), id: \.element.base.id) { index, message in
                                        if index == 0 && !group.sender.isCurrentUser {
                                            // Show sender name for incoming messages
                                            Text(group.sender.profile.displayName)
                                                .font(.footnote)
                                                .foregroundColor(.secondary)
                                                .padding(.leading, 52)
                                                .padding(.bottom, 2)
                                        }
                                        let isLast = index == group.messages.count - 1
                                        let bubbleType: MessagesCollectionCell.BubbleType = isLast ? .tailed : .normal

                                        renderMessage(
                                            message,
                                            bubbleType: bubbleType,
                                        )
                                    }

                                    let isLastGroupByCurrentUser = item == messages.last(where: {
                                        $0.isMessagesGroupSentByCurrentUser
                                    })
                                    if isLastGroupByCurrentUser {
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
                                    }

                                    ForEach(Array(group.unpublished.enumerated()), id: \.element.base.id) { index, message in
                                        let isLast = index == group.unpublished.count - 1
                                        let bubbleType: MessagesCollectionCell.BubbleType = isLast ? .tailed : .normal
                                        renderMessage(
                                            message,
                                            bubbleType: bubbleType,
                                        )
                                    }
                                }
                                .id(group.id)
                            }
                        }
//                        .transition(.slide)
                        .listRowSeparator(.hidden)
                        .listRowInsets(nil)
                        .listRowSpacing(0.0)
                    }
                }
                .animation(.spring(duration: 0.5, bounce: 0.2), value: messages)
            }
            .contentMargins(.horizontal, DesignConstants.Spacing.step2x, for: .scrollContent)
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .scrollPosition($scrollPosition)
        }
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
            .id(message.base.id)
            .onTapGesture {
                onTapMessage(message)
            }

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
