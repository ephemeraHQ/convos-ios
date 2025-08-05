import SwiftUI

struct MessagesTopBar: View {
    enum TrailingItem {
        case share, scan
    }

    let conversation: Conversation
    let invite: Invite
    let untitledConversationPlaceholder: String
    let conversationNamePlaceholder: String
    @Binding var conversationName: String
    @Binding var conversationImage: UIImage?
    var focusState: FocusState<MessagesViewInputFocus?>.Binding
    let onConversationInfoTap: () -> Void
    let onConversationNameEndedEditing: () -> Void
    let onConversationSettings: () -> Void
    let onScanInviteCode: () -> Void
    let trailingItem: TrailingItem = .scan

    @State private var progress: CGFloat = 0.0

    var body: some View {
        ZStack {
            HStack(spacing: 0.0) {
                Button {
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20.0))
                        .padding(8.0)
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
                                .padding(8.0)
                        }
                        .frame(width: 44.0, height: 44.0)
                        .buttonBorderShape(.circle)
                        .buttonStyle(.glass)
                    }
                }
                .offset(x: 88.0 * progress)
            }
            .padding(.horizontal, DesignConstants.Spacing.step4x)
            .onChange(of: focusState.wrappedValue) { _, newValue in
                withAnimation(.bouncy(duration: 0.4, extraBounce: 0.1)) {
                    progress = newValue == .conversationName ? 1.0 : 0.0
                }
            }

            ConversationInfoButton(
                conversation: conversation,
                placeholderName: conversationNamePlaceholder,
                untitledConversationPlaceholder: untitledConversationPlaceholder,
                conversationName: $conversationName,
                conversationImage: $conversationImage,
                focusState: focusState,
                onConversationInfoTapped: onConversationInfoTap,
                onConversationNameEndedEditing: onConversationNameEndedEditing,
                onConversationSettings: onConversationSettings
            )
        }
    }
}

#Preview {
    @Previewable @State var conversationName: String = ""
    @Previewable @State var conversationImage: UIImage?
    @Previewable @FocusState var focusState: MessagesViewInputFocus?

    MessagesTopBar(
        conversation: .mock(),
        invite: .empty,
        untitledConversationPlaceholder: "New convo",
        conversationNamePlaceholder: "Name",
        conversationName: $conversationName,
        conversationImage: $conversationImage,
        focusState: $focusState,
        onConversationInfoTap: {
            focusState = .conversationName
        },
        onConversationNameEndedEditing: {},
        onConversationSettings: {},
        onScanInviteCode: {}
    )
}
