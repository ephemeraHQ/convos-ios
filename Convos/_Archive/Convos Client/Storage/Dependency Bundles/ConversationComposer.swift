import Foundation

struct AnyDraftConversationComposer: DraftConversationComposerProtocol, Hashable {
    private let base: any DraftConversationComposerProtocol
    private let id: UUID

    init(_ base: any DraftConversationComposerProtocol) {
        self.base = base
        self.id = UUID()
    }

    var draftConversationRepository: any DraftConversationRepositoryProtocol {
        base.draftConversationRepository
    }

    var profileSearchRepository: any ProfileSearchRepositoryProtocol {
        base.profileSearchRepository
    }

    var draftConversationWriter: any DraftConversationWriterProtocol {
        base.draftConversationWriter
    }

    var conversationConsentWriter: any ConversationConsentWriterProtocol {
        base.conversationConsentWriter
    }

    var conversationLocalStateWriter: any ConversationLocalStateWriterProtocol {
        base.conversationLocalStateWriter
    }

    static func == (lhs: AnyDraftConversationComposer, rhs: AnyDraftConversationComposer) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

protocol DraftConversationComposerProtocol {
    var draftConversationWriter: any DraftConversationWriterProtocol { get }
    var draftConversationRepository: any DraftConversationRepositoryProtocol { get }
    var profileSearchRepository: any ProfileSearchRepositoryProtocol { get }
    var conversationConsentWriter: any ConversationConsentWriterProtocol { get }
    var conversationLocalStateWriter: any ConversationLocalStateWriterProtocol { get }
}

struct DraftConversationComposer: DraftConversationComposerProtocol {
    let draftConversationWriter: any DraftConversationWriterProtocol
    let draftConversationRepository: any DraftConversationRepositoryProtocol
    let profileSearchRepository: any ProfileSearchRepositoryProtocol
    let conversationConsentWriter: any ConversationConsentWriterProtocol
    let conversationLocalStateWriter: any ConversationLocalStateWriterProtocol
}

struct MockDraftConversationComposer: DraftConversationComposerProtocol {
    let draftConversationWriter: any DraftConversationWriterProtocol = MockDraftConversationWriter()
    let draftConversationRepository: any DraftConversationRepositoryProtocol = MockDraftConversationRepository()
    let profileSearchRepository: any ProfileSearchRepositoryProtocol = MockProfileSearchRepository()
    let conversationConsentWriter: any ConversationConsentWriterProtocol = MockConversationConsentWriter()
    let conversationLocalStateWriter: any ConversationLocalStateWriterProtocol = MockConversationLocalStateWriter()
}
