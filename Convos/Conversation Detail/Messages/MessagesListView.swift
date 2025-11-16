import ConvosCore
import SwiftUI
import SwiftUIIntrospect

struct MessagesListView: View {
    let conversation: Conversation
    @Binding var messages: [AnyMessage]
    let invite: Invite
    let onTapMessage: (AnyMessage) -> Void
    let onTapAvatar: (AnyMessage) -> Void
    let bottomBarHeight: CGFloat
    @State private var scrollPosition: ScrollPosition = ScrollPosition(edge: .bottom)

    var body: some View {
        ScrollViewReader { scrollReader in
            ScrollView {
                LazyVStack(spacing: 0.0) {
                    ForEach($messages, id: \.differenceIdentifier) { message in
                        Group {
                            let isFirstMessage = messages.first?.differenceIdentifier == message.wrappedValue.differenceIdentifier
                            let isLastMessage = messages.last?.differenceIdentifier == message.wrappedValue.differenceIdentifier

                            if isFirstMessage {
                                if conversation.creator.isCurrentUser {
                                    // show the invite
                                    InviteView(invite: invite)
                                } else {
                                    // show convo info
                                    ConversationInfoPreview(conversation: conversation)
                                }

                                // always show the date before the first message
                                let date = MessagesDateFormatter.shared.string(from: message.wrappedValue.base.date)
                                TextTitleContentView(title: date, profile: nil)
                            } else {
                                let bubbleType: MessagesCollectionCell.BubbleType = isLastMessage ? .tailed : .normal

                                switch message.wrappedValue.base.content {
                                case .text(let messageContent):
                                    MessageBubble(
                                        style: bubbleType,
                                        message: messageContent,
                                        isOutgoing: message.wrappedValue.base.sender.isCurrentUser,
                                        profile: message.wrappedValue.base.sender.profile,
                                        onTapAvatar: {}
                                    )
                                default:
                                    EmptyView()
                                }
                            }
                        }
                        .id(message.wrappedValue.differenceIdentifier)
                        .listRowSeparator(.hidden)
                        .listRowInsets(nil)
                        .listRowSpacing(0.0)
                    }
                }
            }
            .onAppear {
                scrollReader.scrollTo(messages.last?.differenceIdentifier, anchor: .bottom)
            }
//            .listStyle(.plain)
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .scrollPosition($scrollPosition)
        }
    }
}
