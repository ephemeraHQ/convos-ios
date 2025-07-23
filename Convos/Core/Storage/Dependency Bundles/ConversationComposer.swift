import Foundation

protocol DraftConversationComposerProtocol {
    var myProfileWriter: any MyProfileWriterProtocol { get }
    var draftConversationWriter: any DraftConversationWriterProtocol { get }
    var draftConversationRepository: any DraftConversationRepositoryProtocol { get }
    var conversationConsentWriter: any ConversationConsentWriterProtocol { get }
    var conversationLocalStateWriter: any ConversationLocalStateWriterProtocol { get }
}

struct DraftConversationComposer: DraftConversationComposerProtocol {
    let myProfileWriter: any MyProfileWriterProtocol
    let draftConversationWriter: any DraftConversationWriterProtocol
    let draftConversationRepository: any DraftConversationRepositoryProtocol
    let conversationConsentWriter: any ConversationConsentWriterProtocol
    let conversationLocalStateWriter: any ConversationLocalStateWriterProtocol
}

struct MockDraftConversationComposer: DraftConversationComposerProtocol {
    let myProfileWriter: any MyProfileWriterProtocol = MockMyProfileWriter()
    let draftConversationWriter: any DraftConversationWriterProtocol = MockDraftConversationWriter()
    let draftConversationRepository: any DraftConversationRepositoryProtocol = MockDraftConversationRepository()
    let conversationConsentWriter: any ConversationConsentWriterProtocol = MockConversationConsentWriter()
    let conversationLocalStateWriter: any ConversationLocalStateWriterProtocol = MockConversationLocalStateWriter()
}
