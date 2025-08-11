import SwiftUI

struct ConversationInfoPresenter<Content: View>: View {
    @Bindable var viewModel: ConversationsViewModel
    @FocusState.Binding var focusState: MessagesViewInputFocus?
    @Binding var sidebarColumnWidth: CGFloat
    @ViewBuilder let content: () -> Content

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass: UserInterfaceSizeClass?
    @Environment(\.safeAreaInsets) private var safeAreaInsets: EdgeInsets

    var body: some View {
        ZStack {
            content()

            if let selectedConversation = viewModel.selectedConversation {
                @Bindable var viewModel = selectedConversation
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
                    .padding(.leading, horizontalSizeClass != .compact ? sidebarColumnWidth : 0.0)

                    Spacer()
                }
                .ignoresSafeArea()
                .allowsHitTesting(true)
                .zIndex(1000)
            }
        }
    }
}

#Preview {
    @Previewable @State var conversationsViewModel: ConversationsViewModel = .mock
    @Previewable @FocusState var focusState: MessagesViewInputFocus?
    @Previewable @State var sidebarColumnWidth: CGFloat = 0
    ConversationInfoPresenter(
        viewModel: conversationsViewModel,
        focusState: $focusState,
        sidebarColumnWidth: $sidebarColumnWidth
    ) {
        EmptyView()
    }
    .withSafeAreaEnvironment()
}
