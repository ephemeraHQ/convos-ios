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

    @State private var showingToolbarButtons: Bool = true
    @State private var presentingDeleteConfirmation: Bool = false
    @State private var isExpanded: Bool = false
    @Namespace private var namespace: Namespace.ID

    private var leadingItemImage: Image {
        switch leadingItem {
        case .close:
            Image(systemName: "xmark")
        case .back:
            Image(systemName: "chevron.left")
        }
    }

    var body: some View {
        HStack {
            ZStack {
                HStack(spacing: 0.0) {
                    if !isExpanded {
                        Group {
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
                            .padding(.leading, DesignConstants.Spacing.step4x)
                        }
                        .transition(AnyTransition.move(edge: .leading).combined(with: .opacity))
                    }

                    Spacer()

                    if !isExpanded {
                        Group {
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
                            .padding(.trailing, DesignConstants.Spacing.step4x)
                        }
                        .transition(AnyTransition.move(edge: .trailing).combined(with: .opacity))
                    }
                }

                GlassEffectContainer {
                    ZStack {
                        if !isExpanded {
                            ConversationToolbarButton(
                                conversation: conversation,
                                conversationImage: $conversationImage,
                                conversationName: conversationName,
                                placeholderName: untitledConversationPlaceholder,
                                action: onConversationInfoTap
                            )
                            .padding(DesignConstants.Spacing.step2x)
                            .clipShape(.rect(cornerRadius: 26.0))
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26.0))
                            .glassEffectID("conversationInfo", in: namespace)
                            .glassEffectTransition(.matchedGeometry)
                        }

                        if isExpanded {
                            QuickEditView(
                                placeholderText: conversationName.isEmpty ? untitledConversationPlaceholder : conversationName,
                                text: $conversationName,
                                image: $conversationImage,
                                focusState: $focusState,
                                focused: .conversationName,
                                onSubmit: onConversationNameEndedEditing,
                                onSettings: onConversationSettings
                            )
                            .frame(maxWidth: 320.0)
                            .padding(DesignConstants.Spacing.step6x)
                            .clipShape(.rect(cornerRadius: 40.0))
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 40.0))
                            .glassEffectID("conversationEditor", in: namespace)
                            .glassEffectTransition(.matchedGeometry)
                        }
                    }
                }
            }
            .onChange(of: viewModelFocus) { _, newValue in
                withAnimation(.bouncy(duration: 0.4, extraBounce: 0.01)) {
                    isExpanded = newValue == .conversationName
                }
            }
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
