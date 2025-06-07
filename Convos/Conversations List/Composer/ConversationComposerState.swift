import Combine
import OrderedCollections
import SwiftUI

@Observable
class ConversationComposerState {
    private let profileSearchRepo: any ProfileSearchRepositoryProtocol
    private(set) var draftConversationRepo: any DraftConversationRepositoryProtocol
    let draftConversationWriter: any DraftConversationWriterProtocol
    let conversationConsentWriter: any ConversationConsentWriterProtocol
    private var cancellables: Set<AnyCancellable> = []
    private(set) var hasSentMessage: Bool = false
    private(set) var messagesRepository: any MessagesRepositoryProtocol

    private var searchTask: Task<Void, Never>?

    var searchText: String = "" {
        didSet {
            performSearch()
        }
    }

    var selectedProfile: ProfileSearchResult?

    var conversationResults: [Conversation] = []
    private(set) var profilesAdded: OrderedSet<ProfileSearchResult> = []
    var profileResults: [ProfileSearchResult] = []

    var showResultsList: Bool {
        return (!profileResults.isEmpty || !conversationResults.isEmpty) && !hasSentMessage
    }

    init(
        profileSearchRepository: any ProfileSearchRepositoryProtocol,
        draftConversationRepo: any DraftConversationRepositoryProtocol,
        draftConversationWriter: any DraftConversationWriterProtocol,
        conversationConsentWriter: any ConversationConsentWriterProtocol,
        messagesRepository: any MessagesRepositoryProtocol
    ) {
        self.profileSearchRepo = profileSearchRepository
        self.draftConversationRepo = draftConversationRepo
        self.draftConversationWriter = draftConversationWriter
        self.messagesRepository = messagesRepository
        self.conversationConsentWriter = conversationConsentWriter
        draftConversationRepo
            .membersPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] members in
                guard let self else { return }
                profilesAdded = OrderedSet<ProfileSearchResult>(members.map {
                    .init(profile: $0, inboxId: $0.id)
                })
            }
            .store(in: &cancellables)
    }

    func add(profile: ProfileSearchResult) {
        searchText = ""
        let memberProfile: MemberProfile = .init(
            inboxId: profile.inboxId,
            name: profile.profile.name,
            username: profile.profile.username,
            avatar: profile.profile.avatar
        )
        Task {
            do {
                try await draftConversationWriter.add(profile: memberProfile)
            } catch {
                Logger.error("Error adding profile: \(error)")
            }
        }
    }

    func remove(profile: ProfileSearchResult) {
        let memberProfile: MemberProfile = .init(
            inboxId: profile.inboxId,
            name: profile.profile.name,
            username: profile.profile.username,
            avatar: profile.profile.avatar
        )
        Task {
            do {
                try await draftConversationWriter.remove(profile: memberProfile)
            } catch {
                Logger.error("Error removing profile: \(error)")
            }
        }
    }

    func didSendMessage() {
        hasSentMessage = true
    }

    private func performSearch() {
        searchTask?.cancel()

        guard !searchText.isEmpty else {
            profileResults = []
            return
        }

        searchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce

            do {
                let results = try await profileSearchRepo.search(using: searchText)
                let filtered = results.filter { !self.profilesAdded.contains($0) }
                self.profileResults = filtered
            } catch {
                Logger.error("Search failed: \(error)")
                self.profileResults = []
            }
        }
    }
}
