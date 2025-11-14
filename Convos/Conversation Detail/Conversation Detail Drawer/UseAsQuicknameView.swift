import ConvosCore
import SwiftUI

struct UseAsQuicknameView: View {
    @Binding var profile: Profile
    let onLearnMore: () -> Void

    var body: some View {
        VStack(spacing: DesignConstants.Spacing.step2x) {
            Button {
                onLearnMore()
            } label: {
                HStack(spacing: DesignConstants.Spacing.step2x) {
                    Image(systemName: "gear")
                        .foregroundStyle(.colorTextPrimaryInverted)
                        .font(.footnote)

                    Text("Use as Quickname in new convos?")
                        .font(.callout)
                        .foregroundStyle(.colorTextPrimaryInverted)
                }
                .padding(.vertical, DesignConstants.Spacing.step3HalfX)
                .padding(.horizontal, DesignConstants.Spacing.step4x)
                .background(
                    DrainingCapsule(
                        fillColor: .colorBackgroundInverted,
                        backgroundColor: .colorFillSecondary,
                        duration: ConversationOnboardingState.useAsQuicknameViewDuration
                    )
                )
            }
            .hoverEffect(.lift)
        }
        .padding(.vertical, DesignConstants.Spacing.step4x)
    }
}

#Preview {
    @Previewable @State var profile: Profile = .mock()
    @Previewable @State var resetId = UUID()

    VStack(spacing: 20) {
        UseAsQuicknameView(
            profile: $profile,
            onLearnMore: {},
        )
        .id(resetId)

        Button("Replay") {
            resetId = UUID()
        }
        .buttonStyle(.borderedProminent)
    }
    .padding()
}
