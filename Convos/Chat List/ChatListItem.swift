import SwiftUI

struct ChatListItem: View {
    let conversationItem: Conversation
    let onTap: () -> Void
    let onPin: () -> Void
    let onToggleRead: () -> Void
    let onToggleMute: () -> Void
    let onDelete: () -> Void

    @State private var isPinning: Bool = false
    @State private var otherParticipant: ConvosSDK.User?
    @State private var lastMessage: ConvosSDK.RawMessageType?

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 12) {
                // Avatar
                AsyncImage(url: otherParticipant?.profile.avatarURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color(.systemGray5)
                }
                .frame(width: 52, height: 52)
                .clipShape(Circle())

                // Chat info
                VStack(alignment: .leading, spacing: 4) {
                    // Username
                    Text(otherParticipant?.profile.username ?? "Unknown")
                        .font(.system(size: 17, weight: conversationItem.isUnread ? .semibold : .regular))
                        .foregroundColor(.primary)

                    // Message preview with timestamp
                    HStack {
                        if let message = lastMessage {
                            HStack(spacing: 4) {
                                Text(message.timestamp.relativeShort()).textCase(.lowercase)
                                Text("•")
                                Text(message.content)
                            }
                            .font(.system(size: 15))
                            .foregroundColor(conversationItem.isUnread ? .primary : .secondary)
                            .lineLimit(1)
                        }

                        Spacer()

                        // Status indicators
                        HStack(spacing: 4) {
                            if conversationItem.isMuted {
                                Image(systemName: "bell.slash.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }

                            if conversationItem.isUnread {
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
        }
        .buttonStyle(ChatListItemButtonStyle())
        .scaleEffect(isPinning ? 0.95 : 1.0)
        .opacity(isPinning ? 0.8 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPinning)
        .contextMenu {
            if conversationItem.isPinned {
                Button("Unpin") {
                    withAnimation {
                        isPinning = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        onPin()
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
                        onPin()
                        withAnimation {
                            isPinning = false
                        }
                    }
                }
            }

            Button(conversationItem.isUnread ? "Mark as Read" : "Mark as Unread") {
                onToggleRead()
            }

            Button(conversationItem.isMuted ? "Unmute" : "Mute") {
                onToggleMute()
            }

            Divider()

            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
    }
}

struct ChatListItemButtonStyle: ButtonStyle {
    @State private var isPressed: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color(.systemGray6) : Color(.systemBackground))
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
