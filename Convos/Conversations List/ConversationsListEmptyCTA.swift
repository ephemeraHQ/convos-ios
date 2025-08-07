import SwiftUI

struct ConversationsListEmptyCTA: View {
    let onStartConvo: () -> Void
    let onJoinConvo: () -> Void
    var body: some View {
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
    }
}
