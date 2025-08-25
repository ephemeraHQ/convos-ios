import ConvosCore
import SwiftUI

extension Conversation {
    var title: String {
        switch kind {
        case .dm:
            return otherMember?.profile.displayName ?? ""
        case .group:
            return displayName
        }
    }
}

struct ListItemView<LeadingContent: View, SubtitleContent: View, AccessoryContent: View>: View {
    let title: String
    let isMuted: Bool
    let isUnread: Bool
    @ViewBuilder let leadingContent: () -> LeadingContent
    @ViewBuilder let subtitle: () -> SubtitleContent
    @ViewBuilder let accessoryContent: () -> AccessoryContent

    var body: some View {
        HStack(spacing: DesignConstants.Spacing.step3x) {
            leadingContent()
                .frame(width: 56.0, height: 56.0)

            VStack(alignment: .leading, spacing: DesignConstants.Spacing.stepX) {
                Text(title)
                    .font(.system(size: 17.0, weight: isUnread ? .semibold : .regular))
                    .foregroundColor(.primary)
                    .truncationMode(.tail)
                    .lineLimit(1)

                HStack {
                    subtitle()
                        .font(.system(size: 15))
                        .foregroundColor(isUnread ? .primary : .secondary)
                        .lineLimit(1)

                    Spacer()

                    HStack(spacing: DesignConstants.Spacing.stepX) {
                        if isMuted {
                            Image(systemName: "bell.slash.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }

                        if isUnread {
                            Circle()
                                .fill(Color.black)
                                .frame(width: 12, height: 12)
                        }
                    }
                }
            }

            accessoryContent()
        }
        .padding(.horizontal, DesignConstants.Spacing.step6x)
        .padding(.vertical, DesignConstants.Spacing.step3x)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.colorBackgroundPrimary)
        .contentShape(Rectangle())
    }
}

struct ConversationsListItem: View {
    let conversation: Conversation

    var body: some View {
        ListItemView(
            title: conversation.title,
            isMuted: conversation.isMuted,
            isUnread: conversation.isUnread,
            leadingContent: {
                ConversationAvatarView(conversation: conversation, conversationImage: nil)
            },
            subtitle: {
                HStack(spacing: DesignConstants.Spacing.stepX) {
                    if let message = conversation.lastMessage {
                        RelativeDateLabel(date: message.createdAt)
                        Text("•")
                        Text(message.text)
                    } else {
                        RelativeDateLabel(date: conversation.createdAt)
                    }
                }
            },
            accessoryContent: {}
        )
    }
}

struct ConversationsListItemButtonStyle: ButtonStyle {
    @State private var isPressed: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color(.systemGray6) : Color(.clear))
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    ConversationsListItem(conversation: .mock())
}
