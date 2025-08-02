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

struct ConversationView: View {
    let conversationRepository: any ConversationRepositoryProtocol
    let myProfileWriter: any MyProfileWriterProtocol
    let messagesRepository: any MessagesRepositoryProtocol
    let outgoingMessageWriter: any OutgoingMessageWriterProtocol
    let conversationConsentWriter: any ConversationConsentWriterProtocol
    let conversationLocalStateWriter: any ConversationLocalStateWriterProtocol
    let groupMetadataWriter: any GroupMetadataWriterProtocol
    let inviteRepository: any InviteRepositoryProtocol
    let conversationState: ConversationState
    @State private var showInfoForConversation: Conversation?
    @State private var presentingCustomizationSheet: Bool = false

    init(dependencies: ConversationViewDependencies) {
        self.conversationRepository = dependencies.conversationRepository
        self.myProfileWriter = dependencies.myProfileWriter
        self.messagesRepository = dependencies.messagesRepository
        self.outgoingMessageWriter = dependencies.outgoingMessageWriter
        self.conversationConsentWriter = dependencies.conversationConsentWriter
        self.conversationLocalStateWriter = dependencies.conversationLocalStateWriter
        self.groupMetadataWriter = dependencies.groupMetadataWriter
        self.inviteRepository = dependencies.inviteRepository
        self.conversationState = ConversationState(
            myProfileRepository: dependencies.myProfileRepository,
            conversationRepository: dependencies.conversationRepository
        )
    }

    private func saveGroupChanges(_ editState: GroupEditState) {
        groupMetadataWriter.saveGroupChanges(
            editState,
            conversation: conversationState.conversation
        )
    }

    var body: some View {
        MessagesContainerView(
            conversationState: conversationState,
            myProfileWriter: myProfileWriter,
            outgoingMessageWriter: outgoingMessageWriter,
            conversationLocalStateWriter: conversationLocalStateWriter
        ) {
            MessagesView(
                messagesRepository: messagesRepository,
                inviteRepository: inviteRepository,
                inputViewHeight: 0.0
            )
            .ignoresSafeArea()
        }
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            if !presentingCustomizationSheet {
                ToolbarItem(placement: .title) {
                    ConversationToolbarButton(
                        conversation: conversationState.conversation,
                        draftTitle: "Untitled"
                    ) {
                        presentingCustomizationSheet = true
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    InviteShareLink(invite: conversationState.conversation.invite)
                }
            }
        }
        .navigationBarBackButtonHidden(presentingCustomizationSheet)
        .groupCustomizationSheet(
            isPresented: $presentingCustomizationSheet,
            editState: conversationState.editState,
        ) {
            saveGroupChanges(conversationState.editState)
        }
    }
}

#Preview {
    ConversationView(dependencies: .mock())
        .ignoresSafeArea()
}
