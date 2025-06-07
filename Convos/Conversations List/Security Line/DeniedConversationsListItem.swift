import SwiftUI

struct DeniedConversationsEmblemView: View {
    var body: some View {
        HStack {
            Image(systemName: "trash.fill")
                .font(.system(size: 24.0))
                .multilineTextAlignment(.center)
                .padding(.vertical, 9.0)
                .padding(.horizontal, 15.0)
                .foregroundStyle(.colorBorderSubtle)
                .aspectRatio(1.0, contentMode: .fit)
        }
        .aspectRatio(1.0, contentMode: .fit)
        .frame(maxHeight: .infinity)
        .background(.colorBorderSubtle2)
        .clipShape(RoundedRectangle(cornerRadius: DesignConstants.CornerRadius.medium))
    }
}

struct DeniedConversationsListItem: View {
    let count: Int
    var body: some View {
        ListItemView(
            title: "Trash",
            isMuted: false,
            isUnread: false,
            leadingContent: {
                DeniedConversationsEmblemView()
            },
            subtitle: {
                Text("\(count) \(count == 1 ? "chat" : "chats")")
            },
            accessoryContent: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 17.0))
                    .foregroundColor(.secondary)
            }
        )
    }
}

#Preview {
    DeniedConversationsListItem(count: 10)
}
