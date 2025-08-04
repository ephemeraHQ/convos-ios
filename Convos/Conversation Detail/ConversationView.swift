import SwiftUI

struct ConversationViewDependencies: Hashable {
    let conversationId: String
    let myProfileWriter: any MyProfileWriterProtocol
    let myProfileRepository: any MyProfileRepositoryProtocol
    let conversationRepository: any ConversationRepositoryProtocol
    let messagesRepository: any MessagesRepositoryProtocol
    let outgoingMessageWriter: any OutgoingMessageWriterProtocol
    let conversationConsentWriter: any ConversationConsentWriterProtocol
    let conversationLocalStateWriter: any ConversationLocalStateWriterProtocol
    let groupMetadataWriter: any GroupMetadataWriterProtocol
    let inviteRepository: any InviteRepositoryProtocol

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.conversationId == rhs.conversationId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(conversationId)
    }
}

extension ConversationViewDependencies {
    static func mock() -> ConversationViewDependencies {
        let messaging = MockMessagingService()
        let conversationId: String = "1"
        return ConversationViewDependencies(
            conversationId: conversationId,
            myProfileWriter: messaging.myProfileWriter(),
            myProfileRepository: messaging.myProfileRepository(),
            conversationRepository: messaging.conversationRepository(for: conversationId),
            messagesRepository: messaging.messagesRepository(for: conversationId),
            outgoingMessageWriter: messaging.messageWriter(for: conversationId),
            conversationConsentWriter: messaging.conversationConsentWriter(),
            conversationLocalStateWriter: messaging.conversationLocalStateWriter(),
            groupMetadataWriter: messaging.groupMetadataWriter(),
            inviteRepository: messaging.inviteRepository(for: conversationId)
        )
    }
}

extension GroupMetadataWriterProtocol {
    func saveGroupChanges(_ editState: GroupEditState, conversation: Conversation) {
        if editState.groupName != conversation.name {
            Task {
                do {
                    try await updateGroupName(
                        groupId: conversation.id,
                        name: editState.groupName
                    )
                } catch {
                    Logger.error("Failed updating group name: \(error)")
                }
            }
        }

        if case .success(let image) = editState.imageState {
            Task {
                do {
                    try await updateGroupImage(
                        conversation: conversation,
                        image: image
                    )
                } catch {
                    Logger.error("Failed updating group image: \(error)")
                }
            }
        }
    }
}

@Observable
class ConversationViewModel {
    var conversation: Conversation = .mock()
    var messages: [AnyMessage] = []
    var invite: Invite = .empty
    var profile: Profile = .mock()
    var untitledConversationPlaceholder: String = "Untitled"
    var conversationNamePlaceholder: String = "Name"
    var displayName: String = ""
    var conversationName: String = ""
    var conversationImage: UIImage?
    var messageText: String = "" {
        didSet {
            sendButtonEnabled = !messageText.isEmpty
        }
    }
    var sendButtonEnabled: Bool = false
    var profileImage: UIImage?
    var focus: MessagesViewInputFocus?

    func onConversationInfoTap() {
        focus = .conversationName
    }

    func onConversationNameEndedEditing() {
        focus = .message
    }

    func onConversationSettings() {
    }

    func onProfilePhotoTap() {
        focus = .displayName
    }

    func onSendMessage() {
        messageText = ""
    }

    func onDisplayNameEndedEditing() {
        focus = .message
    }

    func onProfileSettings() {
    }

    func onScanInviteCode() {
    }
}

struct ConversationView: View {
//    let conversationRepository: any ConversationRepositoryProtocol
//    let myProfileWriter: any MyProfileWriterProtocol
//    let messagesRepository: any MessagesRepositoryProtocol
//    let outgoingMessageWriter: any OutgoingMessageWriterProtocol
//    let conversationConsentWriter: any ConversationConsentWriterProtocol
//    let conversationLocalStateWriter: any ConversationLocalStateWriterProtocol
//    let groupMetadataWriter: any GroupMetadataWriterProtocol
//    let inviteRepository: any InviteRepositoryProtocol
//    let conversationState: ConversationState

//    init(dependencies: ConversationViewDependencies) {
//        self.conversationRepository = dependencies.conversationRepository
//        self.myProfileWriter = dependencies.myProfileWriter
//        self.messagesRepository = dependencies.messagesRepository
//        self.outgoingMessageWriter = dependencies.outgoingMessageWriter
//        self.conversationConsentWriter = dependencies.conversationConsentWriter
//        self.conversationLocalStateWriter = dependencies.conversationLocalStateWriter
//        self.groupMetadataWriter = dependencies.groupMetadataWriter
//        self.inviteRepository = dependencies.inviteRepository
//        self.conversationState = ConversationState(
//            myProfileRepository: dependencies.myProfileRepository,
//            conversationRepository: dependencies.conversationRepository
//        )
//    }

    @State var viewModel: ConversationViewModel
    @FocusState private var focusState: MessagesViewInputFocus?

    var body: some View {
        MessagesView(
            conversation: viewModel.conversation,
            messages: viewModel.messages,
            invite: viewModel.invite,
            profile: viewModel.profile,
            untitledConversationPlaceholder: viewModel.untitledConversationPlaceholder,
            conversationNamePlaceholder: viewModel.conversationNamePlaceholder,
            conversationName: $viewModel.conversationName,
            conversationImage: $viewModel.conversationImage,
            displayName: $viewModel.displayName,
            messageText: $viewModel.messageText,
            sendButtonEnabled: $viewModel.sendButtonEnabled,
            profileImage: $viewModel.profileImage,
            focusState: $focusState,
            onConversationInfoTap: viewModel.onConversationInfoTap,
            onConversationNameEndedEditing: viewModel.onConversationNameEndedEditing,
            onConversationSettings: viewModel.onConversationSettings,
            onProfilePhotoTap: viewModel.onProfilePhotoTap,
            onSendMessage: viewModel.onSendMessage,
            onDisplayNameEndedEditing: viewModel.onDisplayNameEndedEditing,
            onProfileSettings: viewModel.onProfileSettings,
            onScanInviteCode: viewModel.onScanInviteCode
        )
        .onChange(of: viewModel.focus) { _, newValue in
            focusState = newValue
        }
    }
}

#Preview {
    @Previewable @State var viewModel: ConversationViewModel = ConversationViewModel()
    ConversationView(viewModel: viewModel)
}
