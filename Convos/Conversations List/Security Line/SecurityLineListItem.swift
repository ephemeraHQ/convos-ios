import SwiftUI

struct SecurityLineEmblemView: View {
    var body: some View {
        HStack {
            Image(systemName: "shield.fill")
                .font(.system(size: 24.0))
                .multilineTextAlignment(.center)
                .padding(.vertical, 9.0)
                .padding(.horizontal, 15.0)
                .foregroundStyle(.colorTextPrimaryInverted)
                .aspectRatio(1.0, contentMode: .fit)
        }
        .aspectRatio(1.0, contentMode: .fit)
        .frame(maxHeight: .infinity)
        .background(.colorOrange)
        .clipShape(RoundedRectangle(cornerRadius: DesignConstants.CornerRadius.medium))
    }
}

struct SecurityLineListItem: View {
    let count: Int
    var body: some View {
        ListItemView(
            title: "Security",
            isMuted: false,
            isUnread: false,
            leadingContent: {
                SecurityLineEmblemView()
            },
            subtitle: {
                Text("\(count) \(count == 1 ? "chat" : "chats")")
            },
            accessoryContent: {}
        )
    }
}

#Preview {
    SecurityLineListItem(count: 10)
}
