import SwiftUI

extension Conversation {
    var title: String {
        switch kind {
        case .dm:
            return otherMember?.displayName ?? ""
        case .group:
            return topic
        }
    }
}

struct ConversationsListItem: View {
    let conversation: Conversation

    @State private var isPinning: Bool = false

    var body: some View {
        HStack(spacing: 12.0) {
            AsyncImage(url: conversation.creator.avatarURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                MonogramView(name: conversation.title)
            }
            .frame(width: 52.0, height: 52.0)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.title)
                    .font(.system(size: 17.0, weight: conversation.isUnread ? .semibold : .regular))
                    .foregroundColor(.primary)
                    .truncationMode(.tail)
                    .lineLimit(1)

                HStack {
                    if let message = conversation.lastMessage {
                        HStack(spacing: 4) {
                            RelativeDateLabel(date: message.createdAt)
                            Text("•")
                            Text(message.text)
                        }
                        .font(.system(size: 15))
                        .foregroundColor(conversation.isUnread ? .primary : .secondary)
                        .lineLimit(1)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        if conversation.isMuted {
                            Image(systemName: "bell.slash.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }

                        if conversation.isUnread {
                            Circle()
                                .fill(Color.black)
                                .frame(width: 12, height: 12)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .scaleEffect(isPinning ? 0.95 : 1.0)
        .opacity(isPinning ? 0.8 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPinning)
        .contextMenu {
            if conversation.isPinned {
                Button("Unpin") {
                    withAnimation {
                        isPinning = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            isPinning = false
                        }
                    }
                }
            } else {
                Button("Pin") {
                    withAnimation {
                        isPinning = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            isPinning = false
                        }
                    }
                }
            }

            Button(conversation.isUnread ? "Mark as Read" : "Mark as Unread") {
            }

            Button(conversation.isMuted ? "Unmute" : "Mute") {
            }

            Divider()

            Button("Delete", role: .destructive) {
            }
        }
    }
}

struct ConversationsListItemButtonStyle: ButtonStyle {
    @State private var isPressed: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color(.systemGray6) : Color(.systemBackground))
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
