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
    @State private var lastItemIndex: Int?

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
                    ForEach(messages.enumerated(), id: \.element.id) { index, item in
                        Group {
                            switch item {
                            case .date(let dateGroup):
                                TextTitleContentView(title: dateGroup.value, profile: nil)
                                    .padding(.vertical, DesignConstants.Spacing.step2x)

                            case .update(_, let update):
                                TextTitleContentView(title: update.summary, profile: update.profile)
                                    .padding(.vertical, DesignConstants.Spacing.stepX)

                            case .messages(let group):
                                MessagesGroupView(
                                    group: group,
                                    onTapMessage: onTapMessage,
                                    onTapAvatar: onTapAvatar,
                                    animates: lastItemIndex == nil ? false : index > (lastItemIndex ?? 0)
                                )
                            }
                        }
                        .onScrollVisibilityChange { isVisible in
                            guard lastItemIndex == nil else { return }
                            if isVisible && index == messages.count - 1 {
                                lastItemIndex = index
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(nil)
                        .listRowSpacing(0.0)
                    }
                }
//                .scrollTargetLayout()
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .scrollEdgeEffectHidden() // makes no sense, but fixes the flickering profile photo
            .animation(.spring(duration: 0.5, bounce: 0.2), value: messages)
            .contentMargins(.horizontal, DesignConstants.Spacing.step4x, for: .scrollContent)
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .scrollPosition($scrollPosition)
        }
    }
}
