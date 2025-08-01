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

    private func saveGroupChanges(_ editState: GroupEditState) async {
        do {
            if editState.groupName != conversationState.conversation.name {
                try await groupMetadataWriter.updateGroupName(
                    groupId: conversationState.conversation.id,
                    name: editState.groupName
                )
            }

            if case .success(let image) = editState.imageState {
                // Save image using writer
            }
        } catch {
            Logger.error("Failed to save group changes: \(error)")
        }
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
                inviteRepository: inviteRepository
            )
            .ignoresSafeArea()
        }
//        .navigationDestination(item: $showInfoForConversation) { conversation in
//            ConversationInfoView(
//                conversation: conversation,
//                groupMetadataWriter: groupMetadataWriter
//            )
//        }
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
                    let inviteString = conversationState.conversation.invite?.temporaryInviteString ?? ""
                    ShareLink(
                        item: inviteString
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(inviteString.isEmpty)
                }
            }
        }
        .groupCustomizationSheet(
            isPresented: $presentingCustomizationSheet,
            editState: conversationState.editState,
        ) {
            Task {
                await saveGroupChanges(conversationState.editState)
            }
        }
    }
}

#Preview {
    ConversationView(dependencies: .mock())
        .ignoresSafeArea()
}
