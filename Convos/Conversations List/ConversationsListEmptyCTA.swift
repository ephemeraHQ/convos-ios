import SwiftUI

// swiftlint:disable force_unwrapping

struct ConversationsListEmptyCTA: View {
    let onStartConvo: () -> Void
    let onJoinConvo: () -> Void

    @Environment(\.openURL) private var openURL: OpenURLAction

    var body: some View {
        VStack(spacing: 0.0) {
            VStack(alignment: .leading, spacing: DesignConstants.Spacing.step4x) {
                Text("Pop-up private convos")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.colorTextPrimary)
                Text("Chat instantly, with anybody.\nNo accounts. New you every time.")
                    .font(.body)
                    .foregroundStyle(.colorTextSecondary)
                HStack {
                    Button {
                        onStartConvo()
                    } label: {
                        Text("Start a convo")
                            .font(.body)
                    }
                    .convosButtonStyle(.rounded(fullWidth: false))
                    Button {
                        onJoinConvo()
                    } label: {
                        Text("or join one")
                    }
                    .convosButtonStyle(.text)
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(.colorFillMinimal)
            .cornerRadius(32.0)

            Button {
                openURL(URL(string: "https://convos.org/terms-and-privacy")!, prefersInApp: true)
            } label: {
                HStack(spacing: DesignConstants.Spacing.step2x) {
                    Text("Terms & Privacy Policy")
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.colorTextTertiary)
                }
                .font(.caption)
                .foregroundStyle(.colorTextSecondary)
                .padding(.vertical, DesignConstants.Spacing.step4x)
                .padding(.horizontal, DesignConstants.Spacing.step6x)
            }
        }
    }
}

// swiftlint:enable force_unwrapping

#Preview {
    ConversationsListEmptyCTA {
    } onJoinConvo: {
    }
}
