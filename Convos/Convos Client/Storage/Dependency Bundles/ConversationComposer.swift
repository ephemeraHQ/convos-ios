import Foundation

protocol DraftConversationComposerProtocol {
    var draftConversationWriter: any DraftConversationWriterProtocol { get }
    var draftConversationRepository: any DraftConversationRepositoryProtocol { get }
    var profileSearchRepository: any ProfileSearchRepositoryProtocol { get }
}

struct DraftConversationComposer: DraftConversationComposerProtocol {
    let draftConversationWriter: any DraftConversationWriterProtocol
    let draftConversationRepository: any DraftConversationRepositoryProtocol
    let profileSearchRepository: any ProfileSearchRepositoryProtocol
}

struct MockDraftConversationComposer: DraftConversationComposerProtocol {
    let draftConversationWriter: any DraftConversationWriterProtocol = MockDraftConversationWriter()
    let draftConversationRepository: any DraftConversationRepositoryProtocol = MockDraftConversationRepository()
    let profileSearchRepository: any ProfileSearchRepositoryProtocol = MockProfileSearchRepository()
}
