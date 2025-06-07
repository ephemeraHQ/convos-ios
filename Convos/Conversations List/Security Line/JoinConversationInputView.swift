import SwiftUI

protocol JoinConversationInputViewModelType: AnyObject {
    func joinConversation()
    func deleteConversation()
}

struct JoinConversationInputView: View {
    var viewModel: JoinConversationInputViewModelType

    var body: some View {
        VStack(spacing: 0.0) {
            VStack(spacing: DesignConstants.Spacing.step2x) {
                Button("Join the conversation") {
                    viewModel.joinConversation()
                }
                .convosButtonStyle(.rounded(fullWidth: true))

                Button("Delete") {
                    viewModel.deleteConversation()
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

private class MockViewModel: JoinConversationInputViewModelType {
    func joinConversation() {
    }

    func deleteConversation() {
    }
}

#Preview {
    @Previewable var viewModel: JoinConversationInputViewModelType = MockViewModel()
    JoinConversationInputView(viewModel: viewModel)
}
