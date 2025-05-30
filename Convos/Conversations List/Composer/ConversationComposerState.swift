import Combine
import OrderedCollections
import SwiftUI

@Observable
class ConversationComposerState {
    private let profileSearchRepo: any ProfileSearchRepositoryProtocol
    private(set) var draftConversationRepo: any DraftConversationRepositoryProtocol
    let draftConversationWriter: any DraftConversationWriterProtocol
    private var cancellables: Set<AnyCancellable> = []

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
    var selectedConversation: Conversation? {
        didSet {
            draftConversationRepo.selectedConversationId = selectedConversation?.id
        }
    }

    init(
        profileSearchRepository: any ProfileSearchRepositoryProtocol,
        draftConversationRepo: any DraftConversationRepositoryProtocol,
        draftConversationWriter: any DraftConversationWriterProtocol
    ) {
        self.profileSearchRepo = profileSearchRepository
        self.draftConversationRepo = draftConversationRepo
        self.draftConversationWriter = draftConversationWriter
        draftConversationRepo
            .conversationPublisher
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] conversation in
                guard let self else { return }
                profilesAdded = OrderedSet<ProfileSearchResult>(conversation.members.map {
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
