import ConvosCore
import SwiftUI

struct AddQuicknameView: View {
    @Binding var profile: Profile
    @Binding var profileImage: UIImage?
    let onUseProfile: (Profile, UIImage?) -> Void
    let onDismiss: () -> Void

    var body: some View {
        AnimatedOverlayView(
            autoDismiss: true,
            duration: ConversationOnboardingCoordinator.addQuicknameViewDuration,
            onDismiss: onDismiss
        ) { animateOut in
            Button {
                animateOut()
                onUseProfile(profile, profileImage)
            } label: {
                HStack(spacing: DesignConstants.Spacing.stepX) {
                    ProfileAvatarView(
                        profile: profile,
                        profileImage: profileImage
                    )
                    .frame(width: 24.0, height: 24.0)

                    Text("Tap to chat as \(profile.displayName)")
                        .font(.system(size: 16.0))
                        .foregroundStyle(.colorTextPrimaryInverted)
                }
                .padding(.vertical, DesignConstants.Spacing.step3HalfX)
                .padding(.horizontal, DesignConstants.Spacing.step4x)
                .background(
                    DrainingCapsule(
                        fillColor: .colorBackgroundInverted,
                        backgroundColor: .colorFillSecondary,
                        duration: ConversationOnboardingCoordinator.addQuicknameViewDuration
                    )
                )
            }
            .hoverEffect(.lift)
            .padding(.vertical, DesignConstants.Spacing.step4x)
        }
    }
}

#Preview {
    @Previewable @State var profile: Profile = .mock()
    @Previewable @State var profileImage: UIImage?
    @Previewable @State var resetId = UUID()

    VStack(spacing: 20) {
        AddQuicknameView(
            profile: $profile,
            profileImage: $profileImage,
            onUseProfile: { _, _ in },
            onDismiss: {}
        )
        .id(resetId)

        Button("Replay") {
            resetId = UUID()
        }
        .buttonStyle(.borderedProminent)
    }
    .padding()
}
