import ConvosCore
import SwiftUI

struct UseAsQuicknameView: View {
    @Binding var profile: Profile
    let onUseAsQuickname: () -> Void
    let onDismiss: () -> Void

    @State private var presentingLearnMore: Bool = false

    var body: some View {
        AnimatedOverlayView(
            autoDismiss: true,
            duration: ConversationOnboardingCoordinator.useAsQuicknameViewDuration,
            onDismiss: onDismiss
        ) { animateOut in
            VStack(spacing: DesignConstants.Spacing.step2x) {
                Button {
                    animateOut()
                    onUseAsQuickname()
                } label: {
                    HStack(spacing: DesignConstants.Spacing.step2x) {
                        Image(systemName: "gear")
                            .foregroundStyle(.colorTextPrimaryInverted)
                            .font(.system(size: 14.0))

                        Text("Use as Quickname in new convos?")
                            .font(.system(size: 16.0))
                            .foregroundStyle(.colorTextPrimaryInverted)
                    }
                    .padding(.vertical, DesignConstants.Spacing.step3HalfX)
                    .padding(.horizontal, DesignConstants.Spacing.step4x)
                    .background(
                        DrainingCapsule(
                            fillColor: .colorBackgroundInverted,
                            backgroundColor: .colorFillSecondary,
                            duration: ConversationOnboardingCoordinator.useAsQuicknameViewDuration
                        )
                    )
                }
                .hoverEffect(.lift)

                Button {
                    animateOut()
                    presentingLearnMore = true
                } label: {
                    HStack(spacing: DesignConstants.Spacing.stepX) {
                        Image(systemName: "lanyardcard.fill")
                            .foregroundStyle(.colorTextTertiary)
                            .font(.caption)
                        Text("Learn more about Quickname")
                            .foregroundStyle(.colorTextSecondary)
                            .font(.caption)
                    }
                    .padding(DesignConstants.Spacing.step3x)
                }
                .hoverEffect(.lift)
            }
            .selfSizingSheet(isPresented: $presentingLearnMore) {
                WhatIsQuicknameView {
                    presentingLearnMore = false
                    onUseAsQuickname()
                }
            }
            .padding(.vertical, DesignConstants.Spacing.step4x)
        }
    }
}

#Preview {
    @Previewable @State var profile: Profile = .mock()
    @Previewable @State var resetId = UUID()

    VStack(spacing: 20) {
        UseAsQuicknameView(
            profile: $profile,
            onUseAsQuickname: {},
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
