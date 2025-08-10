import SwiftUI

struct ConversationInfoPresenter<Content: View>: View {
    @Bindable var viewModel: ConversationViewModel
    @FocusState.Binding var focusState: MessagesViewInputFocus?
    @ViewBuilder let content: () -> Content

    @Environment(\.safeAreaInsets) private var safeAreaInsets: EdgeInsets

    var body: some View {
        ZStack {
            content()

            VStack {
                ConversationInfoButton(
                    conversation: viewModel.conversation,
                    placeholderName: viewModel.conversationNamePlaceholder,
                    untitledConversationPlaceholder: viewModel.untitledConversationPlaceholder,
                    conversationName: $viewModel.conversationName,
                    conversationImage: $viewModel.conversationImage,
                    focusState: $focusState,
                    viewModelFocus: viewModel.focus,
                    onConversationInfoTapped: viewModel.onConversationInfoTap,
                    onConversationNameEndedEditing: viewModel.onConversationNameEndedEditing,
                    onConversationSettings: viewModel.onConversationSettings
                )
                .padding(.top, safeAreaInsets.top)

                Spacer()
            }
            .ignoresSafeArea()
            .allowsHitTesting(true)
            .zIndex(1000)
        }
    }
}

#Preview {
    @Previewable @State var conversationViewModel: ConversationViewModel = .mock
    @Previewable @FocusState var focusState: MessagesViewInputFocus?
    ConversationInfoPresenter(
        viewModel: conversationViewModel,
        focusState: $focusState
    ) {
        EmptyView()
    }
    .withSafeAreaEnvironment()
}
