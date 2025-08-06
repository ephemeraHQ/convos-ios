import SwiftUI

struct MessagesTopBar: View {
    enum LeadingItem {
        case close, back
    }
    enum TrailingItem {
        case share, scan
    }

    let conversation: Conversation
    let invite: Invite
    let untitledConversationPlaceholder: String
    let conversationNamePlaceholder: String
    @Binding var conversationName: String
    @Binding var conversationImage: UIImage?
    @FocusState.Binding var focusState: MessagesViewInputFocus?
    let viewModelFocus: MessagesViewInputFocus?
    let onConversationInfoTap: () -> Void
    let onConversationNameEndedEditing: () -> Void
    let onConversationSettings: () -> Void
    let onScanInviteCode: () -> Void
    let onDeleteConversion: () -> Void
    let leadingItem: LeadingItem
    let trailingItem: TrailingItem
    let confirmDeletionBeforeDismissal: Bool
    @Environment(\.dismiss) var dismiss: DismissAction

    @State private var progress: CGFloat = 0.0
    @State private var presentingDeleteConfirmation: Bool = false

    private var leadingItemImage: Image {
        switch leadingItem {
        case .close:
            Image(systemName: "xmark")
        case .back:
            Image(systemName: "chevron.left")
        }
    }

    var body: some View {
        Group {
            ZStack {
                HStack(spacing: 0.0) {
                    Button {
                        if confirmDeletionBeforeDismissal {
                            presentingDeleteConfirmation = true
                        } else {
                            dismiss()
                        }
                    } label: {
                        leadingItemImage
                            .font(.system(size: 20.0))
                            .padding(4.0)
                    }
                    .confirmationDialog("", isPresented: $presentingDeleteConfirmation) {
                        Button("Delete", role: .destructive) {
                            onDeleteConversion()
                            dismiss()
                        }

                        Button("Keep") {
                            dismiss()
                        }
                    }
                    .frame(width: 44.0, height: 44.0)
                    .buttonBorderShape(.circle)
                    .buttonStyle(.glass)
                    .offset(x: -88.0 * progress)

                    Spacer()

                    Group {
                        switch trailingItem {
                        case .share:
                            InviteShareLink(invite: invite)
                                .frame(width: 44.0, height: 44.0)
                                .glassEffect(.regular.interactive())
                        case .scan:
                            Button {
                                onScanInviteCode()
                            } label: {
                                Image(systemName: "qrcode.viewfinder")
                                    .font(.system(size: 20.0))
                                    .padding(4.0)
                            }
                            .frame(width: 44.0, height: 44.0)
                            .buttonBorderShape(.circle)
                            .buttonStyle(.glass)
                        }
                    }
                    .offset(x: 88.0 * progress)
                }
                .onChange(of: viewModelFocus) { _, newValue in
                    withAnimation(.bouncy(duration: 0.5, extraBounce: 0.2)) {
                        progress = newValue == .conversationName ? 1.0 : 0.0
                    }
                }

                ConversationInfoButton(
                    conversation: conversation,
                    placeholderName: conversationNamePlaceholder,
                    untitledConversationPlaceholder: untitledConversationPlaceholder,
                    conversationName: $conversationName,
                    conversationImage: $conversationImage,
                    focusState: $focusState,
                    viewModelFocus: viewModelFocus,
                    onConversationInfoTapped: onConversationInfoTap,
                    onConversationNameEndedEditing: onConversationNameEndedEditing,
                    onConversationSettings: onConversationSettings
                )
            }
            .padding(.horizontal, DesignConstants.Spacing.step4x)
        }
    }
}

#Preview {
    @Previewable @State var conversationName: String = ""
    @Previewable @State var conversationImage: UIImage?
    @Previewable @State var viewModelFocus: MessagesViewInputFocus?
    @Previewable @FocusState var focusState: MessagesViewInputFocus?

    MessagesTopBar(
        conversation: .mock(),
        invite: .empty,
        untitledConversationPlaceholder: "New convo",
        conversationNamePlaceholder: "Name",
        conversationName: $conversationName,
        conversationImage: $conversationImage,
        focusState: $focusState,
        viewModelFocus: viewModelFocus,
        onConversationInfoTap: {
            focusState = .conversationName
        },
        onConversationNameEndedEditing: {},
        onConversationSettings: {},
        onScanInviteCode: {},
        onDeleteConversion: {},
        leadingItem: .close,
        trailingItem: .scan,
        confirmDeletionBeforeDismissal: false
    )
}
