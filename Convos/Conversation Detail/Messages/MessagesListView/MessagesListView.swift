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
                    ForEach(messages, id: \.id) { item in
                        Group {
                            switch item {
                            case .date(let dateGroup):
                                TextTitleContentView(title: dateGroup.value, profile: nil)
                                    .padding(.vertical, DesignConstants.Spacing.step2x)

                            case .update(_, let update):
                                TextTitleContentView(title: update.summary, profile: update.profile)
                                    .padding(.vertical, DesignConstants.Spacing.stepX)

                            case .messages(let group):
                                let isLastGroupByCurrentUser = item == messages.last(where: {
                                    $0.isMessagesGroupSentByCurrentUser
                                })

                                MessagesGroupView(
                                    group: group,
                                    isLastGroupByCurrentUser: isLastGroupByCurrentUser,
                                    onTapMessage: onTapMessage,
                                    onTapAvatar: onTapAvatar
                                )
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(nil)
                        .listRowSpacing(0.0)
                    }
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .scrollEdgeEffectHidden()
            .animation(.spring(duration: 0.5, bounce: 0.2), value: messages)
            .contentMargins(.horizontal, DesignConstants.Spacing.step2x, for: .scrollContent)
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .scrollPosition($scrollPosition)
        }
    }
}
