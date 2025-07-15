import SwiftUI

struct JoinConversationInputView: View {
    let onJoinConversation: () -> Void
    let onDeleteConversation: () -> Void

    var body: some View {
        VStack(spacing: 0.0) {
            VStack(spacing: DesignConstants.Spacing.step2x) {
                Button("Join the conversation") {
                    onJoinConversation()
                }
                .convosButtonStyle(.rounded(fullWidth: true))

                Button("Delete") {
                    onDeleteConversation()
                }
                .convosButtonStyle(.text)

                Text("No one is notified if you delete it")
                    .font(.caption)
                    .foregroundStyle(.colorTextSecondary)
                    .padding(.top, DesignConstants.Spacing.step2x)
            }
            .padding(.horizontal, DesignConstants.Spacing.step3x)
            .padding(.vertical, DesignConstants.Spacing.step4x)
        }
        .background(.colorBackgroundPrimary)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.colorBorderSubtle2)
                .frame(height: 1.0)
        }
    }
}

#Preview {
    JoinConversationInputView {
    } onDeleteConversation: {
    }
}
