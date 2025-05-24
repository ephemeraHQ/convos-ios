import Foundation

protocol DraftConversationComposerProtocol {
    var draftConversationRepository: any ConversationRepositoryProtocol { get }
    var profileSearchRepository: any ProfileSearchRepositoryProtocol { get }
    var messagesRepository: any MessagesRepositoryProtocol { get }
    var outgoingMessageWriter: any OutgoingMessageWriterProtocol { get }
}

struct DraftConversationComposer: DraftConversationComposerProtocol {
    let draftConversationRepository: any ConversationRepositoryProtocol
    let profileSearchRepository: any ProfileSearchRepositoryProtocol
    let messagesRepository: any MessagesRepositoryProtocol
    let outgoingMessageWriter: any OutgoingMessageWriterProtocol
}

struct MockDraftConversationComposer: DraftConversationComposerProtocol {
    let draftConversationRepository: any ConversationRepositoryProtocol = MockDraftConversationRepository()
    let profileSearchRepository: any ProfileSearchRepositoryProtocol = MockProfileSearchRepository()
    let messagesRepository: any MessagesRepositoryProtocol = MockMessagesRepository(
        conversation: Conversation.mock(id: Conversation.draftPrimaryKey)
    )
    let outgoingMessageWriter: any OutgoingMessageWriterProtocol = MockOutgoingMessageWriter()
}
