import SwiftUI

struct PinnedConversationsGrid: View {
    let conversations: [Conversation]
    let onTapChat: (Conversation) -> Void
    let onUnpin: (Conversation) -> Void
    let onToggleRead: (Conversation) -> Void
    let onToggleMute: (Conversation) -> Void
    let onDelete: (Conversation) -> Void

    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 24), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 24) {
            ForEach(conversations) { conversation in
                Button {
                    onTapChat(conversation)
                } label: {
                    VStack(spacing: 8) {
                        ConversationAvatarView(conversation: conversation)
                            .frame(width: 72, height: 72)
                            .overlay(
                                Circle()
                                    .stroke(Color(.systemGray6), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                            .overlay(
                                // Unread indicator
                                conversation.isUnread ? AnyView(
                                    Circle()
                                        .fill(Color.black)
                                        .frame(width: 12, height: 12)
                                        .offset(x: 26, y: -26)
                                ) : AnyView(EmptyView())
                            )

                        let displayName = conversation.kind == .group
                            ? conversation.name ?? "Group"
                        : conversation.otherMember?.profile.username ?? "Unknown"

                        Text(displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PinnedChatButtonStyle())
                .contextMenu {
                    Button("Unpin") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            onUnpin(conversation)
                        }
                    }

                    Button(conversation.isUnread ? "Mark as Read" : "Mark as Unread") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            onToggleRead(conversation)
                        }
                    }

                    Button(conversation.isMuted ? "Unmute" : "Mute") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            onToggleMute(conversation)
                        }
                    }

                    Divider()

                    Button("Delete", role: .destructive) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            onDelete(conversation)
                        }
                    }
                }
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.8)
                            .combined(with: .opacity)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7)),
                        removal: .opacity
                            .animation(.easeOut(duration: 0.2))
                    )
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: conversations)
    }
}

struct PinnedChatButtonStyle: ButtonStyle {
    @State private var isPressed: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

#Preview {
    PinnedConversationsGrid(
        conversations: [
        ],
        onTapChat: { _ in },
        onUnpin: { _ in },
        onToggleRead: { _ in },
        onToggleMute: { _ in },
        onDelete: { _ in }
    )
    .background(Color(.systemBackground))
}
