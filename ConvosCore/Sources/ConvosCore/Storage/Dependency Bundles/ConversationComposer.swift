import Foundation

public protocol DraftConversationComposerProtocol {
    var myProfileWriter: any MyProfileWriterProtocol { get }
    var draftConversationWriter: any DraftConversationWriterProtocol { get }
    var draftConversationRepository: any DraftConversationRepositoryProtocol { get }
    var conversationConsentWriter: any ConversationConsentWriterProtocol { get }
    var conversationLocalStateWriter: any ConversationLocalStateWriterProtocol { get }
    var conversationMetadataWriter: any ConversationMetadataWriterProtocol { get }
}

struct DraftConversationComposer: DraftConversationComposerProtocol {
    let myProfileWriter: any MyProfileWriterProtocol
    let draftConversationWriter: any DraftConversationWriterProtocol
    let draftConversationRepository: any DraftConversationRepositoryProtocol
    let conversationConsentWriter: any ConversationConsentWriterProtocol
    let conversationLocalStateWriter: any ConversationLocalStateWriterProtocol
    let conversationMetadataWriter: any ConversationMetadataWriterProtocol
}

struct MockDraftConversationComposer: DraftConversationComposerProtocol {
    let myProfileWriter: any MyProfileWriterProtocol = MockMyProfileWriter()
    let draftConversationWriter: any DraftConversationWriterProtocol = MockDraftConversationWriter()
    let draftConversationRepository: any DraftConversationRepositoryProtocol = MockDraftConversationRepository()
    let conversationConsentWriter: any ConversationConsentWriterProtocol = MockConversationConsentWriter()
    let conversationLocalStateWriter: any ConversationLocalStateWriterProtocol = MockConversationLocalStateWriter()
    let conversationMetadataWriter: any ConversationMetadataWriterProtocol = MockConversationMetadataWriter()
}
