import SwiftUI

struct SetupQuicknameSuccessView: View {
    var body: some View {
        Group {
            HStack(spacing: DesignConstants.Spacing.stepX) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.colorGreen)

                Text("Quickname saved")
                    .font(.callout)
                    .foregroundStyle(.colorTextPrimary)
            }
            .padding(.vertical, DesignConstants.Spacing.step3HalfX)
            .padding(.horizontal, DesignConstants.Spacing.step4x)
        }
        .background(
            Capsule()
                .fill(.colorFillMinimal)
        )
    }
}

#Preview {
    SetupQuicknameSuccessView()
}

struct SetupQuicknameView: View {
    let autoDismiss: Bool

    var body: some View {
        Button {
        } label: {
            HStack(spacing: DesignConstants.Spacing.stepX) {
                Image(systemName: "arrow.down.left")
                    .foregroundStyle(.colorTextPrimaryInverted)
                Text("Tap to add your name and pic")
                    .font(.callout)
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
                            duration: ConversationOnboardingState.setupQuicknameViewDuration
                        )
                    } else {
                        Capsule()
                            .fill(.colorBackgroundInverted)
                    }
                }
            )
        }
        .transition(.blurReplace)
        .disabled(true)
        .hoverEffect(.lift)
        .padding(.vertical, DesignConstants.Spacing.step4x)
    }
}

#Preview("Auto Dismiss") {
    @Previewable @State var resetId = UUID()

    VStack(spacing: 20) {
        SetupQuicknameView(
            autoDismiss: true,
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
        )
        .id(resetId)

        Button("Replay") {
            resetId = UUID()
        }
        .buttonStyle(.borderedProminent)
    }
    .padding()
}
