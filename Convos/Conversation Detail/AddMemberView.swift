import SwiftUI

struct AddMemberView: View {
    let conversation: Conversation
    let messagingService: any MessagingServiceProtocol
    @Environment(\.dismiss) private var dismiss: DismissAction

    @State private var searchText: String = ""
    @State private var isSearching: Bool = false
    @State private var searchResults: [Profile] = []
    @State private var selectedMembers: Set<String> = []
    @State private var isAdding: Bool = false
    @State private var showingAlert: Bool = false
    @State private var alertMessage: String = ""

    private var canAddMembers: Bool {
        !selectedMembers.isEmpty && !isAdding
    }

    private var existingMemberIds: Set<String> {
        Set(conversation.members.map { $0.id })
    }

    var body: some View {
        VStack(spacing: 0) {
            CustomToolbarView(onBack: { dismiss() }, rightContent: {
                let action = {
                    Task {
                        await addSelectedMembers()
                    }
                    return ()
                }
                Button(action: action) {
                    Text("Add")
                        .foregroundColor(canAddMembers ? .blue : .gray)
                        .font(.system(size: 16, weight: .medium))
                }
                .padding(.vertical, 10.0)
                .padding(.horizontal, DesignConstants.Spacing.step2x)
                .disabled(!canAddMembers)
            })

            // Search Section
            VStack(spacing: 16) {
                SearchBar(text: $searchText, isSearching: $isSearching, onSearchButtonClicked: {
                    Task {
                        await performSearch()
                    }
                })

                if !selectedMembers.isEmpty {
                    SelectedMembersView(
                        selectedProfiles: searchResults.filter { selectedMembers.contains($0.id) },
                        onRemove: { profileId in
                            selectedMembers.remove(profileId)
                        }
                    )
                }
            }
            .padding()

            // Results Section
            if isSearching {
                ProgressView("Searching...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchResults.isEmpty && !searchText.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)

                    Text("No users found")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("Try searching with a different username or wallet address")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !searchResults.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(searchResults, id: \.id) { profile in
                            AddMemberRow(
                                profile: profile,
                                isSelected: selectedMembers.contains(profile.id),
                                isExistingMember: existingMemberIds.contains(profile.id),
                                onToggle: { profileId in
                                    if selectedMembers.contains(profileId) {
                                        selectedMembers.remove(profileId)
                                    } else {
                                        selectedMembers.insert(profileId)
                                    }
                                }
                            )

                            if profile.id != searchResults.last?.id {
                                Divider()
                                    .padding(.leading, 60)
                            }
                        }
                    }
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .padding()
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)

                    Text("Add Members")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("Search for users by username or wallet address to add them to the group")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarHidden(true)
        .alert("Add Members", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .overlay(
            isAdding ? Color.black.opacity(0.3) : Color.clear
        )
        .overlay(
            isAdding ? ProgressView("Adding members...")
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(10)
                .shadow(radius: 10) : nil
        )
    }

    private func performSearch() async {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }

        isSearching = true

        do {
            // @lourou: Replace with actual user search via messaging service
            // For now, simulate search with mock data
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay

            let mockResults = generateMockSearchResults(for: searchText)

            await MainActor.run {
                searchResults = mockResults
                isSearching = false
            }
        } catch {
            await MainActor.run {
                searchResults = []
                isSearching = false
                alertMessage = "Search failed: \(error.localizedDescription)"
                showingAlert = true
            }
        }
    }

    private func addSelectedMembers() async {
        guard !selectedMembers.isEmpty else { return }

        isAdding = true

        do {
            let memberInboxIds = Array(selectedMembers)
            let metadataWriter = messagingService.groupMetadataWriter()

            try await metadataWriter.addGroupMembers(
                groupId: conversation.id,
                memberInboxIds: memberInboxIds
            )

            await MainActor.run {
                alertMessage = "Successfully added \(selectedMembers.count) member(s) to the group"
                showingAlert = true
                selectedMembers.removeAll()

                // Clear search after adding
                searchText = ""
                searchResults = []
            }

            // Dismiss after a short delay
            try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
            await MainActor.run {
                dismiss()
            }
        } catch {
            await MainActor.run {
                alertMessage = "Failed to add members: \(error.localizedDescription)"
                showingAlert = true
                isAdding = false
            }
        }
    }

    private func generateMockSearchResults(for query: String) -> [Profile] {
        // Mock search results for demo purposes
        let mockUsers = [
            Profile(id: "search1", name: "Sarah Johnson", username: "sarahj", avatar: nil),
            Profile(id: "search2", name: "Mike Chen", username: "mikechen", avatar: nil),
            Profile(id: "search3", name: "Emma Wilson", username: "emmaw", avatar: nil),
            Profile(id: "search4", name: "David Kim", username: "davidk", avatar: nil),
            Profile(id: "search5", name: "Lisa Rodriguez", username: "lisar", avatar: nil)
        ]

        return mockUsers.filter { user in
            user.name.lowercased().contains(query.lowercased()) ||
            user.username.lowercased().contains(query.lowercased())
        }
    }
}

// MARK: - Supporting Views

struct SearchBar: View {
    @Binding var text: String
    @Binding var isSearching: Bool
    let onSearchButtonClicked: () -> Void

    var body: some View {
        HStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search by username or address", text: $text)
                    .onSubmit {
                        onSearchButtonClicked()
                    }

                if !text.isEmpty {
                    let action = { text = "" }
                    Button(action: action) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(10)

            if !text.isEmpty {
                Button("Search") {
                    onSearchButtonClicked()
                }
                .foregroundColor(.blue)
                .disabled(isSearching)
            }
        }
    }
}

struct SelectedMembersView: View {
    let selectedProfiles: [Profile]
    let onRemove: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selected (\(selectedProfiles.count))")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(selectedProfiles, id: \.id) { profile in
                        SelectedMemberChip(
                            profile: profile,
                            onRemove: { onRemove(profile.id) }
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

struct SelectedMemberChip: View {
    let profile: Profile
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            ProfileAvatarView(profile: profile)
                .frame(width: 24, height: 24)

            Text(profile.displayName)
                .font(.caption)
                .lineLimit(1)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }
}

struct AddMemberRow: View {
    let profile: Profile
    let isSelected: Bool
    let isExistingMember: Bool
    let onToggle: (String) -> Void

    var body: some View {
        let action = {
            if !isExistingMember {
                onToggle(profile.id)
            }
        }
        Button(action: action) {
            HStack {
                ProfileAvatarView(profile: profile)
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text("@\(profile.username)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isExistingMember {
                    Text("Member")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                } else {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .blue : .secondary)
                        .font(.title3)
                }
            }
            .padding()
        }
        .disabled(isExistingMember)
        .opacity(isExistingMember ? 0.6 : 1.0)
    }
}

#Preview {
    let members = [
        ConversationMember.mock(name: "Alice"),
        ConversationMember.mock(name: "Mary"),
    ]

    let groupConversation = Conversation(
        id: "group1",
        inboxId: UUID().uuidString,
        creator: members[0],
        createdAt: Date(),
        consent: .allowed,
        kind: .group,
        name: "Test Group",
        description: "A test group",
        members: members,
        otherMember: nil,
        messages: [],
        isPinned: false,
        isUnread: false,
        isMuted: false,
        lastMessage: nil,
        imageURL: nil,
        isDraft: false
    )

    AddMemberView(conversation: groupConversation, messagingService: MockMessagingService())
}
