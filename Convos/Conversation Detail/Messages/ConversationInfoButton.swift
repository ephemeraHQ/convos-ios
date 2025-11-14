import ConvosCore
import SwiftUI

struct ConversationInfoButton<InfoView: View>: View {
    let conversation: Conversation
    let placeholderName: String
    let untitledConversationPlaceholder: String
    let subtitle: String
    @Binding var conversationName: String
    @Binding var conversationImage: UIImage?
    @Binding var presentingConversationSettings: Bool
    @FocusState.Binding var focusState: MessagesViewInputFocus?
    let focusCoordinator: FocusCoordinator?
    let showsExplodeNowButton: Bool
    let onConversationInfoTapped: () -> Void
    let onConversationNameEndedEditing: () -> Void
    let onConversationSettings: () -> Void
    let onExplodeNow: () -> Void
    @ViewBuilder let infoView: () -> InfoView

    @State private var progress: CGFloat = 0.0
    @State private var showingExplodeConfirmation: Bool = false
    @Namespace private var namespace: Namespace.ID

    var body: some View {
        PrimarySecondaryContainerView(
            progress: progress,
            primaryProperties: .init(
                cornerRadius: 26.0,
                padding: DesignConstants.Spacing.step2x,
                fixedSizeHorizontal: false
            ),
            secondaryProperties: .init(
                cornerRadius: 40.0,
                padding: DesignConstants.Spacing.step6x,
                fixedSizeHorizontal: true
            )
        ) {
            ConversationToolbarButton(
                conversation: conversation,
                conversationImage: $conversationImage,
                conversationName: conversationName,
                placeholderName: untitledConversationPlaceholder,
                subtitle: subtitle,
                action: onConversationInfoTapped
            )
        } secondaryContent: {
            VStack(spacing: DesignConstants.Spacing.step4x) {
                QuickEditView(
                    placeholderText: conversationName.isEmpty ? placeholderName : conversationName,
                    text: $conversationName,
                    image: $conversationImage,
                    focusState: $focusState,
                    focused: .conversationName,
                    onSubmit: onConversationNameEndedEditing,
                    onSettings: onConversationSettings)

                if showsExplodeNowButton {
                    Button {
                        showingExplodeConfirmation = true
                    } label: {
                        Text("Explode now")
                    }
                    .buttonStyle(RoundedDestructiveButtonStyle(fullWidth: true))
                    .confirmationDialog(
                        "",
                        isPresented: $showingExplodeConfirmation
                    ) {
                        Button("Explode", role: .destructive) {
                            onExplodeNow()
                        }

                        Button("Cancel") {
                            showingExplodeConfirmation = false
                        }
                    }
                }
            }
            .matchedTransitionSource(
                id: "convo-info-transition-source",
                in: namespace
            )
            .sheet(isPresented: $presentingConversationSettings) {
                infoView()
                    .navigationTransition(
                        .zoom(
                            sourceID: "convo-info-transition-source",
                            in: namespace
                        )
                    )
            }
        }
        .onChange(of: focusCoordinator?.currentFocus) { _, newValue in
            withAnimation(.bouncy(duration: 0.5, extraBounce: 0.2)) {
                progress = newValue == .conversationName ? 1.0 : 0.0
            }
        }
    }
}

#Preview {
    @Previewable @State var conversationName: String = ""
    @Previewable @State var conversationImage: UIImage?
    @Previewable @State var focusCoordinator: FocusCoordinator? = FocusCoordinator(horizontalSizeClass: nil)
    @Previewable @State var presentingConversationSettings: Bool = false
    @Previewable @FocusState var focusState: MessagesViewInputFocus?

    let conversation: Conversation = .mock()
    let placeholderName: String = conversation.name ?? "Name"

    ConversationInfoButton(
        conversation: conversation,
        placeholderName: placeholderName,
        untitledConversationPlaceholder: "Untitled",
        subtitle: "Customize",
        conversationName: $conversationName,
        conversationImage: $conversationImage,
        presentingConversationSettings: $presentingConversationSettings,
        focusState: $focusState,
        focusCoordinator: focusCoordinator,
        showsExplodeNowButton: true,
        onConversationInfoTapped: {
            focusCoordinator?.moveFocus(to: .conversationName)
        },
        onConversationNameEndedEditing: {
            focusCoordinator?.moveFocus(to: nil)
        },
        onConversationSettings: {},
        onExplodeNow: {},
        infoView: {
            EmptyView()
        }
    )
}
