import SwiftUI

struct SetupQuicknameView: View {
    let autoDismiss: Bool
    let onAddName: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        AnimatedOverlayView(
            autoDismiss: autoDismiss,
            duration: ConversationOnboardingCoordinator.setupQuicknameViewDuration,
            onDismiss: onDismiss
        ) { animateOut in
            Button {
                animateOut()
                onAddName()
            } label: {
                HStack(spacing: DesignConstants.Spacing.stepX) {
                    Image(systemName: "arrow.down.left")
                        .foregroundStyle(.colorTextPrimaryInverted)
                    Text("Tap to change your ID")
                        .font(.system(size: 16.0))
                        .foregroundStyle(.colorTextPrimaryInverted)
                }
                .padding(.vertical, DesignConstants.Spacing.step3HalfX)
                .padding(.horizontal, DesignConstants.Spacing.step4x)
                .background(
                    ZStack {
                        if autoDismiss {
                            DrainingCapsule(
                                fillColor: .colorBackgroundInverted,
                                backgroundColor: .colorFillSecondary,
                                duration: ConversationOnboardingCoordinator.setupQuicknameViewDuration
                            )
                        } else {
                            Capsule()
                                .fill(.colorBackgroundInverted)
                        }
                    }
                )
            }
            .hoverEffect(.lift)
            .padding(.vertical, DesignConstants.Spacing.step4x)
        }
    }
}

#Preview("Auto Dismiss") {
    @Previewable @State var resetId = UUID()

    VStack(spacing: 20) {
        SetupQuicknameView(
            autoDismiss: true,
            onAddName: {},
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

#Preview("No Auto Dismiss") {
    @Previewable @State var resetId = UUID()

    VStack(spacing: 20) {
        SetupQuicknameView(
            autoDismiss: false,
            onAddName: {},
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
