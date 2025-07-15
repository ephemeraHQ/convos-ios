import Combine
import OrderedCollections
import SwiftUI

@Observable
class ConversationComposerState {
    private let profileSearchRepo: any ProfileSearchRepositoryProtocol
    let draftConversationRepo: any DraftConversationRepositoryProtocol
    let draftConversationWriter: any DraftConversationWriterProtocol
    let conversationConsentWriter: any ConversationConsentWriterProtocol
    let conversationLocalStateWriter: any ConversationLocalStateWriterProtocol
    private var cancellables: Set<AnyCancellable> = []
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

    private(set) var showProfileSearchHeader: Bool = true

    var showResultsList: Bool {
        return (!profileResults.isEmpty || !conversationResults.isEmpty) && showProfileSearchHeader
    }

    init(
        profileSearchRepository: any ProfileSearchRepositoryProtocol,
        draftConversationRepo: any DraftConversationRepositoryProtocol,
        draftConversationWriter: any DraftConversationWriterProtocol,
        conversationConsentWriter: any ConversationConsentWriterProtocol,
        conversationLocalStateWriter: any ConversationLocalStateWriterProtocol,
        messagesRepository: any MessagesRepositoryProtocol
    ) {
        self.profileSearchRepo = profileSearchRepository
        self.draftConversationRepo = draftConversationRepo
        self.draftConversationWriter = draftConversationWriter
        self.messagesRepository = messagesRepository
        self.conversationConsentWriter = conversationConsentWriter
        self.conversationLocalStateWriter = conversationLocalStateWriter
        draftConversationRepo
            .membersPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] members in
                guard let self else { return }
                Logger.info("Publishing members with count: \(members.count)")
                profilesAdded = OrderedSet<ProfileSearchResult>(members.map {
                    .init(profile: $0.profile, inboxId: $0.id)
                })
            }
            .store(in: &cancellables)
        self.draftConversationWriter
            .sentMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
            guard let self else { return }
            showProfileSearchHeader = false
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
