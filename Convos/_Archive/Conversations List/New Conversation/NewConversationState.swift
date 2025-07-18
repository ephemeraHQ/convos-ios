import Combine
import OrderedCollections
import SwiftUI

@Observable
class NewConversationState {
    let draftConversationRepo: any DraftConversationRepositoryProtocol
    let draftConversationWriter: any DraftConversationWriterProtocol
    let conversationConsentWriter: any ConversationConsentWriterProtocol
    let conversationLocalStateWriter: any ConversationLocalStateWriterProtocol
    private var cancellables: Set<AnyCancellable> = []
    private(set) var messagesRepository: any MessagesRepositoryProtocol

    private var searchTask: Task<Void, Never>?

    init(
        draftConversationRepo: any DraftConversationRepositoryProtocol,
        draftConversationWriter: any DraftConversationWriterProtocol,
        conversationConsentWriter: any ConversationConsentWriterProtocol,
        conversationLocalStateWriter: any ConversationLocalStateWriterProtocol,
        messagesRepository: any MessagesRepositoryProtocol
    ) {
        self.draftConversationRepo = draftConversationRepo
        self.draftConversationWriter = draftConversationWriter
        self.messagesRepository = messagesRepository
        self.conversationConsentWriter = conversationConsentWriter
        self.conversationLocalStateWriter = conversationLocalStateWriter
        self.draftConversationWriter
            .sentMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
            guard let self else { return }
//            showProfileSearchHeader = false
        }
        .store(in: &cancellables)
    }
}
