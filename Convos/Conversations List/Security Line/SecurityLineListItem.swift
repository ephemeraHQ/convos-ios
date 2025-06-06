import SwiftUI

struct SecurityLineEmblemView: View {
    var body: some View {
        GeometryReader { geometry in
            HStack {
                Image(systemName: "shield.fill")
                    .font(.system(size: 24.0))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 9.0)
                    .padding(.horizontal, 15.0)
                    .foregroundStyle(.colorTextPrimaryInverted)
                    .aspectRatio(1.0, contentMode: .fill)
            }
            .frame(width: geometry.size.height, height: geometry.size.height)
            .background(.colorOrange)
            .clipShape(RoundedRectangle(cornerRadius: DesignConstants.CornerRadius.medium))
        }
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
            }
        )
    }
}

#Preview {
    SecurityLineListItem(count: 10)
}
