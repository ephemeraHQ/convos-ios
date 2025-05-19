import SwiftUI

struct ChatListNavigationBar: View {
    @State var userState: UserState

    let signOut: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                AsyncImage(url: userState.currentUser?.profile.avatarURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    MonogramView(name: userState.currentUser?.profile.name ?? "")
                }
                .frame(width: 32.0, height: 32.0)
                .clipShape(Circle())

                Text(userState.currentUser?.profile.name ?? "")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
            }

            Spacer()

            HStack {
                Button {
                    // composer
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 20))
                }
            }
            .foregroundColor(.primary)
        }
        .padding(.horizontal, 16.0)
        .frame(height: 52.0)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(.systemGray4))
                .opacity(0.5),
            alignment: .bottom
        )
    }
}

// swiftlint:disable force_unwrapping
//#Preview {
//    ChatListNavigationBar(
//        currentIdentity: CTUser(
//            id: "preview",
//            username: "preview.eth",
//            avatarURL: URL(string: "https://picsum.photos/200")!
//        ),
//        onIdentityTap: {},
//        onQRTap: {},
//        onWalletTap: {},
//        onComposeTap: {}
//    )
//}
// swiftlint:enable force_unwrapping
