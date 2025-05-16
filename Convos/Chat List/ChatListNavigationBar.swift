import SwiftUI

struct ChatListNavigationBar: View {
    @State var userState: UserState
    let onIdentityTap: () -> Void
    let onQRTap: () -> Void
    let onWalletTap: () -> Void
    let onComposeTap: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Identity selector button
            Button {
                onIdentityTap()
            } label: {
                HStack(spacing: 8) {
                    AsyncImage(url: userState.currentUser?.profile.avatarURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        MonogramView(name: userState.currentUser?.profile.name ?? "")
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())

                    Text(userState.currentUser?.profile.name ?? "")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.primary)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()

            // Action buttons
            HStack(spacing: 20) {
//                Button(action: onQRTap) {
//                    Image(systemName: "qrcode")
//                        .font(.system(size: 20))
//                }
//
//                Button(action: onWalletTap) {
//                    Image(systemName: "creditcard")
//                        .font(.system(size: 20))
//                }

                Button(action: onComposeTap) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 20))
                }
            }
            .foregroundColor(.primary)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
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
