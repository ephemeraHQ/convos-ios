import SwiftUI

struct ConversationsListNavigationBar: View {
    @State var userState: UserState

    let onCompose: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        HStack(spacing: 0.0) {
            HStack(spacing: DesignConstants.Spacing.step4x) {
                HStack(spacing: 0.0) {
                    if let user = userState.currentUser {
                        ProfileAvatarView(profile: user.profile)
                            .padding(DesignConstants.Spacing.step2x)
                    }
                    Text(userState.currentUser?.profile.name ?? "")
                        .font(.system(size: 16.0, weight: .regular))
                        .foregroundColor(.colorTextPrimary)
                        .padding(.vertical, 10.0)
                }

                Spacer()

                HStack {
                    Button {
                        onCompose()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 24.0))
                            .padding(.bottom, 4.0) // vertical align based on square
                    }
                }
                .foregroundColor(.colorTextPrimary)
                .padding(.horizontal, DesignConstants.Spacing.step2x)
            }
            .padding(DesignConstants.Spacing.step4x)
        }
        .background(.colorBackgroundPrimary)
    }
}

#Preview {
    @Previewable @State var userState: UserState = .init(
        userRepository: MockUserRepository()
    )

    ConversationsListNavigationBar(userState: userState, onCompose: {}) {
    }
}
