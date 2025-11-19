import ConvosCore
import SwiftUI

struct MessagesGroupItemView: View {
    let message: AnyMessage
    let bubbleType: MessagesCollectionCell.BubbleType
    let showsSentStatus: Bool
    let onTapMessage: (AnyMessage) -> Void
    let onTapAvatar: (AnyMessage) -> Void
    let animates: Bool

    @State private var isAppearing: Bool = true

    private var isPublished: Bool {
        message.base.status == .published
    }

    var body: some View {
        VStack {
            switch message.base.content {
            case .text(let text):
                MessageBubble(
                    style: bubbleType,
                    message: text,
                    isOutgoing: message.base.sender.isCurrentUser,
                    profile: message.base.sender.profile,
                    onTapAvatar: { onTapAvatar(message) }
                )
                .zIndex(200)
                .id(message.base.id)
                .onTapGesture {
                    onTapMessage(message)
                }
                .scaleEffect(isAppearing ? 0.9 : 1.0)
                .rotationEffect(
                    .radians(
                        isAppearing
                        ? (message.base.source == .incoming ? -0.05 : 0.05)
                        : 0
                    )
                )
                .offset(
                    x: isAppearing
                    ? (message.base.source == .incoming ? -20 : 20)
                    : 0,
                    y: isAppearing ? 40 : 0
                )
            case .emoji(let text):
                Text(text)
                    .id(message.base.id)
                    .font(.largeTitle)
            case .attachment(let url):
                AttachmentPlaceholder(url: url, isOutgoing: message.base.sender.isCurrentUser)
                    .id(message.base.id)
                    .onTapGesture {
                        onTapMessage(message)
                    }

            case .attachments(let urls):
                MultipleAttachmentsPlaceholder(urls: urls, isOutgoing: message.base.sender.isCurrentUser)
                    .id(message.base.id)
                    .onTapGesture {
                        onTapMessage(message)
                    }

            case .update:
                // Updates are handled at the item level, not here
                EmptyView()
            }

            if showsSentStatus {
                HStack(spacing: DesignConstants.Spacing.stepHalf) {
                    Spacer()
                    Text("Sent")
                    Image(systemName: "checkmark")
                }
                .padding(.bottom, DesignConstants.Spacing.stepHalf)
                .font(.caption)
                .foregroundStyle(.colorTextSecondary)
                .id("sent-status-\(message.base.sender.id)")
                .transition(.blurReplace)
                .zIndex(100)
            }
        }
        .transition(
            .asymmetric(
                insertion: .identity,      // no transition on insert
                removal: .opacity
            )
        )
        .onAppear {
            guard isAppearing else { return }

            if animates {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isAppearing = false
                }
            } else {
                isAppearing = false
            }
        }
    }
}

// MARK: - Placeholder Views for Attachments

private struct AttachmentPlaceholder: View {
    let url: URL
    let isOutgoing: Bool

    var body: some View {
        HStack {
            if isOutgoing { Spacer() }

            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 200, height: 150)
                .overlay(
                    VStack {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                        Text("Attachment")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                )

            if !isOutgoing { Spacer() }
        }
    }
}

private struct MultipleAttachmentsPlaceholder: View {
    let urls: [URL]
    let isOutgoing: Bool

    var body: some View {
        HStack {
            if isOutgoing { Spacer() }

            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 200, height: 150)
                .overlay(
                    VStack {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                        Text("\(urls.count) Attachments")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                )

            if !isOutgoing { Spacer() }
        }
    }
}

// MARK: - Previews

#Preview("Text Message - Incoming") {
    MessagesGroupItemView(
        message: .message(Message.mock(
            text: "Hello, how are you doing today?",
            sender: .mock(isCurrentUser: false),
            status: .published
        )),
        bubbleType: .normal,
        showsSentStatus: false,
        onTapMessage: { _ in },
        onTapAvatar: { _ in },
        animates: true
    )
    .padding()
}

#Preview("Text Message - Outgoing") {
    MessagesGroupItemView(
        message: .message(Message.mock(
            text: "I'm doing great, thanks for asking!",
            sender: .mock(isCurrentUser: true),
            status: .published
        )),
        bubbleType: .tailed,
        showsSentStatus: true,
        onTapMessage: { _ in },
        onTapAvatar: { _ in },
        animates: true
    )
    .padding()
}

#Preview("Unpublished Message") {
    MessagesGroupItemView(
        message: .message(Message.mock(
            text: "This message is still sending...",
            sender: .mock(isCurrentUser: true),
            status: .unpublished
        )),
        bubbleType: .normal,
        showsSentStatus: false,
        onTapMessage: { _ in },
        onTapAvatar: { _ in },
        animates: true
    )
    .padding()
}

#Preview("Emoji Message") {
    MessagesGroupItemView(
        message: .message(Message.mock(
            text: "😊👍🎉",
            sender: .mock(isCurrentUser: false),
            status: .published
        )),
        bubbleType: .tailed,
        showsSentStatus: false,
        onTapMessage: { _ in },
        onTapAvatar: { _ in },
        animates: true
    )
    .padding()
}
