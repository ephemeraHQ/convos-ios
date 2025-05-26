import OrderedCollections
import SwiftUI

@Observable
class ConversationComposerViewModel {
    private let profileSearchRepo: any ProfileSearchRepositoryProtocol
    private var searchTask: Task<Void, Never>?

    var searchText: String = "" {
        didSet {
            performSearch()
        }
    }

    var conversationResults: [Conversation] = []
    var profilesAdded: OrderedSet<ProfileSearchResult> = []
    var profileResults: [ProfileSearchResult] = []

    init(
        profileSearchRepository: any ProfileSearchRepositoryProtocol
    ) {
        self.profileSearchRepo = profileSearchRepository
    }

    func add(profile: ProfileSearchResult) {
        searchText = ""
        profilesAdded.append(profile)
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

struct ConversationComposerContentView: View {
    @State private var selectedProfile: ProfileSearchResult?
    @State private var viewModel: ConversationComposerViewModel

    init(
        profileSearchRepository: any ProfileSearchRepositoryProtocol,
        selectedProfile: ProfileSearchResult? = nil
    ) {
        self.selectedProfile = selectedProfile
        _viewModel = State(
            initialValue: .init(profileSearchRepository: profileSearchRepository)
        )
    }

    private let headerHeight: CGFloat = 72.0

    var resultsList: some View {
        List {
            ForEach(viewModel.conversationResults, id: \.id) { conversation in
                FlashingListRowButton {
                } content: {
                    HStack(spacing: DesignConstants.Spacing.step3x) {
                        ConversationAvatarView(conversation: conversation)
                            .frame(maxHeight: 40.0)

                        VStack(alignment: .leading, spacing: 0.0) {
                            Text(conversation.title)
                                .font(.system(size: 16.0))
                                .foregroundStyle(.colorTextPrimary)

                            switch conversation.kind {
                            case .dm:
                                Text(conversation.otherMember?.username ?? "")
                                    .font(.system(size: 14.0))
                                    .foregroundStyle(.colorTextSecondary)
                            case .group:
                                Text(conversation.memberNamesString)
                                    .font(.system(size: 14.0))
                                    .foregroundStyle(.colorTextSecondary)
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundStyle(.colorTextSecondary)
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .listRowSpacing(0.0)
            }

            ForEach(viewModel.profileResults, id: \.id) { profileResult in
                let profile = profileResult.profile
                FlashingListRowButton {
                    viewModel.add(profile: profileResult)
                } content: {
                    HStack(spacing: DesignConstants.Spacing.step3x) {
                        ProfileAvatarView(profile: profile)
                            .frame(height: 40.0)

                        VStack(alignment: .leading, spacing: 0.0) {
                            Text(profile.name)
                                .font(.system(size: 16.0))
                                .foregroundStyle(.colorTextPrimary)
                            Text(profile.username)
                                .font(.system(size: 14.0))
                                .foregroundStyle(.colorTextSecondary)
                        }

                        Spacer()
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .listRowSpacing(0.0)
            }
        }
        .listStyle(.plain)
        .listRowSpacing(0.0)
        .padding(0)
    }

    var body: some View {
        VStack(spacing: 0.0) {
            // profile search header
            HStack(alignment: .top,
                   spacing: DesignConstants.Spacing.step2x) {
                Text("To")
                    .font(.system(size: 16.0))
                    .foregroundStyle(.colorTextSecondary)
                    .frame(height: headerHeight)

                ConversationComposerProfilesField(searchText: $viewModel.searchText,
                                                  selectedProfile: $selectedProfile,
                                                  profiles: $viewModel.profilesAdded)

                Button {
                } label: {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 24.0))
                        .foregroundStyle(.colorTextPrimary)
                        .padding(.horizontal, DesignConstants.Spacing.step2x)
                }
                .opacity(viewModel.searchText.isEmpty ? 1.0 : 0.2)
                .frame(height: headerHeight)
            }
                   .contentShape(Rectangle())
                   .onTapGesture {
                       selectedProfile = nil
                   }
                   .padding(.horizontal, DesignConstants.Spacing.step4x)

            resultsList

            Spacer().frame(height: 0.0)
        }
    }
}

#Preview {
    ConversationComposerContentView(
        profileSearchRepository: MockProfileSearchRepository()
    )
}
