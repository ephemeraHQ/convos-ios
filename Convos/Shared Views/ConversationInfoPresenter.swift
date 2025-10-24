import SwiftUI

struct ConversationInfoPresenter<Content: View>: View {
    let viewModel: ConversationViewModel?
    @FocusState.Binding var focusState: MessagesViewInputFocus?
    @Binding var sidebarColumnWidth: CGFloat
    @ViewBuilder let content: () -> Content

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass: UserInterfaceSizeClass?
    @Environment(\.safeAreaInsets) private var safeAreaInsets: EdgeInsets

    var body: some View {
        ZStack {
            content()

            VStack {
                if let viewModel = viewModel, viewModel.showsInfoView {
                    ConversationInfoButtonWrapper(
                        viewModel: viewModel,
                        focusState: $focusState
                    )
                        .padding(.top, safeAreaInsets.top)
                        .padding(.leading, horizontalSizeClass != .compact ? sidebarColumnWidth : 0.0)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .identity
                        ))
                }

                Spacer()
            }
            .animation(.bouncy(duration: 0.4, extraBounce: 0.15), value: viewModel != nil)
            .ignoresSafeArea()
            .allowsHitTesting(true)
            .zIndex(1000)
        }
    }
}

private struct ConversationInfoButtonWrapper: View {
    @Bindable var viewModel: ConversationViewModel
    @FocusState.Binding var focusState: MessagesViewInputFocus?

    var body: some View {
        ConversationInfoButton(
            conversation: viewModel.conversation,
            placeholderName: viewModel.conversationNamePlaceholder,
            untitledConversationPlaceholder: viewModel.untitledConversationPlaceholder,
            subtitle: viewModel.conversationInfoSubtitle,
            conversationName: $viewModel.editingConversationName,
            conversationImage: $viewModel.conversationImage,
            presentingConversationSettings: $viewModel.presentingConversationSettings,
            focusState: $focusState,
            viewModelFocus: viewModel.focus,
            showsExplodeNowButton: viewModel.showsExplodeNowButton,
            onConversationInfoTapped: viewModel.onConversationInfoTap,
            onConversationNameEndedEditing: viewModel.onConversationNameEndedEditing,
            onConversationSettings: viewModel.onConversationSettings,
            onExplodeNow: viewModel.explodeConvo
        ) {
            ConversationInfoView(viewModel: viewModel)
        }
    }
}

#Preview {
    @Previewable @State var conversationViewModel: ConversationViewModel? = .mock
    @Previewable @FocusState var focusState: MessagesViewInputFocus?
    @Previewable @State var sidebarColumnWidth: CGFloat = 0
    ConversationInfoPresenter(
        viewModel: conversationViewModel,
        focusState: $focusState,
        sidebarColumnWidth: $sidebarColumnWidth
    ) {
        EmptyView()
    }
    .withSafeAreaEnvironment()
}
