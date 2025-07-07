import SwiftUI

struct ConversationInfoView: View {
    let conversation: Conversation
    let messagingService: any MessagingServiceProtocol
    @Environment(\.dismiss) private var dismiss: DismissAction
    @State private var showAllMembers: Bool = false
    @State private var showGroupEdit: Bool = false
    @State private var showAddMember: Bool = false

    private var conversationWithAllMembers: Conversation {
        // For group conversations, ensure current user is included in member list for proper display
        if conversation.kind == .group {
            return conversation.withCurrentUserIncluded()
        }
        return conversation
    }

    var body: some View {
        VStack(spacing: 0) {
            CustomToolbarView(onBack: { dismiss() }, rightContent: {
                if conversation.kind == .group {
                    EditGroupButton(action: { showGroupEdit = true })
                }
            })

            // Content
            switch conversation.kind {
            case .dm:
                DMInfoView(conversation: conversation)
            case .group:
                GroupInfoView(
                    conversation: conversationWithAllMembers,
                    messagingService: messagingService,
                    showAllMembers: $showAllMembers,
                    showAddMember: $showAddMember
                )
            }
        }
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $showAllMembers) {
            AllMembersView(conversation: conversationWithAllMembers, messagingService: messagingService)
        }
        .navigationDestination(isPresented: $showGroupEdit) {
            GroupEditView(conversation: conversation, messagingService: messagingService)
        }
        .navigationDestination(isPresented: $showAddMember) {
            AddMemberView(conversation: conversation, messagingService: messagingService)
        }
    }
}

// MARK: - DM Info View
struct DMInfoView: View {
    let conversation: Conversation

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Profile Header
                if let otherMember = conversation.otherMember {
                    VStack(spacing: 16) {
                        ProfileAvatarView(profile: otherMember)
                            .frame(width: 80, height: 80)

                        VStack(spacing: 4) {
                            Text(otherMember.displayName)
                                .font(.title2)
                                .fontWeight(.semibold)

                            Text("@\(otherMember.username)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 20)
                }

                // Actions Section
                VStack(spacing: 12) {
                    DMActionButton(title: "Message", systemImage: "message.fill") {
                        // Handle message action
                    }

                    DMActionButton(title: "Clear Chat History", systemImage: "trash", isDestructive: true) {
                        // Handle clear chat
                    }
                }
                .padding(.horizontal)

                // Settings Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Settings")
                        .font(.headline)
                        .padding(.horizontal)

                    VStack(spacing: 0) {
                        SettingsRow(title: "Notifications", systemImage: "bell") {
                            // Handle notifications
                        }

                        Divider()
                            .padding(.leading, 40)

                        SettingsRow(title: "Media Auto-Download", systemImage: "square.and.arrow.down") {
                            // Handle media settings
                        }
                    }
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }

                Spacer()
            }
        }
    }
}

// MARK: - Group Info View
struct GroupInfoView: View {
    let conversation: Conversation
    let messagingService: any MessagingServiceProtocol
    @Binding var showAllMembers: Bool
    @Binding var showAddMember: Bool
    @State private var memberRoles: [String: MemberRole] = [:]

    private var displayedMembers: [Profile] {
        let allMembers = conversation.withCurrentUserIncluded().members
        let sortedMembers = allMembers.sorted { member1, member2 in
            sortMembersByRole(member1, member2)
        }
        return Array(sortedMembers.prefix(6))
    }

    private func sortMembersByRole(_ member1: Profile, _ member2: Profile) -> Bool {
        // Show "You" (current user) first
        if member1.id == "current" { return true }
        if member2.id == "current" { return false }

        let role1 = memberRoles[member1.id] ?? .member
        let role2 = memberRoles[member2.id] ?? .member

        // Sort by role hierarchy: superAdmin > admin > member
        let priority1 = rolePriority(role1)
        let priority2 = rolePriority(role2)

        if priority1 != priority2 {
            return priority1 > priority2
        }

        // Same role, sort alphabetically by name
        return member1.displayName < member2.displayName
    }

    private func rolePriority(_ role: MemberRole) -> Int {
        switch role {
        case .superAdmin: return 3
        case .admin: return 2
        case .member: return 1
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Group Header
                VStack(spacing: 16) {
                    ConversationAvatarView(conversation: conversation)
                        .frame(width: 80, height: 80)

                    VStack(spacing: 4) {
                        Text(conversation.name ?? "Group Chat")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("\(conversation.members.count) members")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    if let description = conversation.description, !description.isEmpty {
                        Text(description)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding(.top, 20)

                // Members Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("\(conversation.withCurrentUserIncluded().members.count) Members")
                            .font(.headline)
                        Spacer()
                        AddMemberButton(action: { showAddMember = true })
                    }
                    .padding(.horizontal)

                    LazyVStack(spacing: 0) {
                        ForEach(displayedMembers, id: \.id) { member in
                            MemberRow(
                                member: member,
                                conversationID: conversation.id,
                                messagingService: messagingService,
                                canDeleteMembers: true,
                                onMemberRemoved: { _ in
                                    // @lourou: Refresh conversation data
                                }
                            )

                            if member.id != displayedMembers.last?.id {
                                Divider()
                                    .padding(.leading, 60)
                            }
                        }

                        if conversation.withCurrentUserIncluded().members.count > 6 {
                            SeeAllMembersButton(
                                memberCount: conversation.withCurrentUserIncluded().members.count,
                                action: { showAllMembers = true }
                            )
                        }
                    }
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }

                // Actions Section
                VStack(spacing: 12) {
                    GroupActionButton(title: "Clear Chat History", systemImage: "trash", isDestructive: true) {
                        // Handle clear chat
                    }

                    GroupActionButton(
                        title: "Leave Group",
                        systemImage: "rectangle.portrait.and.arrow.right",
                        isDestructive: true) {
                        // Handle leave group
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
        }
        .onAppear {
            Task {
                await loadMemberRoles()
            }
        }
    }

    private func loadMemberRoles() async {
        do {
            let groupMembers = try await messagingService.groupPermissionsRepository()
                .getGroupMembers(for: conversation.id)

            await MainActor.run {
                var roles: [String: MemberRole] = [:]

                // Map inbox IDs to member IDs and store roles
                for groupMember in groupMembers {
                    // Find corresponding profile by inbox ID
                    if let profile = conversation.withCurrentUserIncluded().members
                        .first(where: { $0.id == groupMember.inboxId }) {
                        roles[profile.id] = groupMember.role
                    }
                }

                self.memberRoles = roles
            }
        } catch {
            Logger.error("Failed to load member roles: \(error)")
        }
    }
}

// MARK: - Supporting Views
struct DMActionButton: View {
    let title: String
    let systemImage: String
    let isDestructive: Bool
    let action: () -> Void

    init(title: String, systemImage: String, isDestructive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isDestructive = isDestructive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundColor(isDestructive ? .red : .primary)
                Text(title)
                    .foregroundColor(isDestructive ? .red : .primary)
                Spacer()
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }
}

struct GroupActionButton: View {
    let title: String
    let systemImage: String
    let isDestructive: Bool
    let action: () -> Void

    init(title: String, systemImage: String, isDestructive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isDestructive = isDestructive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundColor(isDestructive ? .red : .blue)
                Text(title)
                    .foregroundColor(isDestructive ? .red : .primary)
                Spacer()
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }
}

struct SettingsRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundColor(.primary)
                    .frame(width: 20)
                Text(title)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding()
        }
    }
}

struct MemberRow: View {
    let member: Profile
    let conversationID: String
    let messagingService: (any MessagingServiceProtocol)?
    let canDeleteMembers: Bool
    let onMemberRemoved: ((String) -> Void)?

    @State private var showingDeleteAlert: Bool = false
    @State private var isDeleting: Bool = false
    @State private var memberRole: MemberRole = .member

    init(
        member: Profile,
        conversationID: String,
        messagingService: (any MessagingServiceProtocol)? = nil,
        canDeleteMembers: Bool = false,
        onMemberRemoved: ((String) -> Void)? = nil) {
        self.member = member
        self.conversationID = conversationID
        self.messagingService = messagingService
        self.canDeleteMembers = canDeleteMembers
        self.onMemberRemoved = onMemberRemoved
    }

    var body: some View {
        HStack {
            ProfileAvatarView(profile: member)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName)
                    .font(.body)
                    .fontWeight(.medium)

                Text("@\(member.username)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !memberRole.displayName.isEmpty {
                Text(memberRole.displayName)
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
            }

            if canDeleteMembers && !isCurrentUser {
                let action = { showingDeleteAlert = true }
                Button(action: action) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                        .font(.title3)
                }
                .disabled(isDeleting)
                .opacity(isDeleting ? 0.5 : 1.0)
            }
        }
        .padding()
        .task {
            await loadMemberRole()
        }
        .alert("Remove Member", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                Task {
                    await removeMember()
                }
            }
        } message: {
            Text("Are you sure you want to remove \(member.displayName) from this group?")
        }
    }

    private var isCurrentUser: Bool {
        // @lourou: Get actual current user ID from messaging service
        member.id == "current"
    }

    private func loadMemberRole() async {
        guard let messagingService = messagingService else { return }

        do {
            let permissionsRepo = messagingService.groupPermissionsRepository()
            let role = try await permissionsRepo.getMemberRole(
                memberInboxId: member.id,
                in: conversationID
            )

            await MainActor.run {
                memberRole = role
            }
        } catch {
            Logger.error("Failed to load member role for \(member.id): \(error)")
            // Keep default .member role
        }
    }

    private func removeMember() async {
        guard let messagingService = messagingService else { return }

        isDeleting = true

        do {
            let metadataWriter = messagingService.groupMetadataWriter()
            try await metadataWriter.removeGroupMembers(
                groupId: conversationID,
                memberInboxIds: [member.id]
            )
            await MainActor.run {
                onMemberRemoved?(member.id)
                isDeleting = false
            }
        } catch {
            await MainActor.run {
                // @lourou: Show error alert
                Logger.error("Failed to remove member \(member.id): \(error)")
                isDeleting = false
            }
        }
    }
}

struct SeeAllMembersButton: View {
    let memberCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text("See all \(memberCount)")
                    .foregroundColor(.blue)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding()
        }
    }
}

struct EditGroupButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "pencil")
                .font(.system(size: 24.0))
                .foregroundColor(.primary)
                .padding(.vertical, 10.0)
                .padding(.horizontal, DesignConstants.Spacing.step2x)
        }
    }
}

struct AddMemberButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .foregroundColor(.primary)
        }
    }
}

// MARK: - All Members View
struct AllMembersView: View {
    let conversation: Conversation
    let messagingService: any MessagingServiceProtocol
    @Environment(\.dismiss) private var dismiss: DismissAction
    @State private var showAddMember: Bool = false
    @State private var memberRoles: [String: MemberRole] = [:]

    private var sortedMembers: [Profile] {
        let allMembers = conversation.withCurrentUserIncluded().members
        return allMembers.sorted { member1, member2 in
            sortMembersByRole(member1, member2)
        }
    }

    private func sortMembersByRole(_ member1: Profile, _ member2: Profile) -> Bool {
        // Show "You" (current user) first
        if member1.id == "current" { return true }
        if member2.id == "current" { return false }

        let role1 = memberRoles[member1.id] ?? .member
        let role2 = memberRoles[member2.id] ?? .member

        // Sort by role hierarchy: superAdmin > admin > member
        let priority1 = rolePriority(role1)
        let priority2 = rolePriority(role2)

        if priority1 != priority2 {
            return priority1 > priority2
        }

        // Same role, sort alphabetically by name
        return member1.displayName < member2.displayName
    }

    private func rolePriority(_ role: MemberRole) -> Int {
        switch role {
        case .superAdmin: return 3
        case .admin: return 2
        case .member: return 1
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            CustomToolbarView(onBack: { dismiss() }, rightContent: {
                AddMemberButton(action: { showAddMember = true })
            })

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sortedMembers, id: \.id) { member in
                        MemberRow(
                            member: member,
                            conversationID: conversation.id,
                            messagingService: messagingService,
                            canDeleteMembers: true,
                            onMemberRemoved: { _ in
                                // @lourou: Refresh conversation data
                            }
                        )

                        if member.id != sortedMembers.last?.id {
                            Divider()
                                .padding(.leading, 60)
                        }
                    }
                }
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding()
            }
        }
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $showAddMember) {
            AddMemberView(conversation: conversation, messagingService: messagingService)
        }
        .onAppear {
            Task {
                await loadMemberRoles()
            }
        }
    }

    private func loadMemberRoles() async {
        do {
            let groupMembers = try await messagingService.groupPermissionsRepository()
                .getGroupMembers(for: conversation.id)

            await MainActor.run {
                var roles: [String: MemberRole] = [:]

                // Map inbox IDs to member IDs and store roles
                for groupMember in groupMembers {
                    // Find corresponding profile by inbox ID
                    if let profile = conversation.withCurrentUserIncluded().members
                        .first(where: { $0.id == groupMember.inboxId }) {
                        roles[profile.id] = groupMember.role
                    }
                }

                self.memberRoles = roles
            }
        } catch {
            Logger.error("Failed to load member roles: \(error)")
        }
    }
}

#Preview("DM Conversation") {
    let dmProfile = Profile(
        id: "user1",
        name: "John Doe",
        username: "johndoe",
        avatar: nil
    )

    let currentUser = Profile(
        id: "current",
        name: "Me",
        username: "me",
        avatar: nil
    )

    let dmConversation = Conversation(
        id: "dm1",
        creator: currentUser,
        createdAt: Date(),
        consent: .allowed,
        kind: .dm,
        name: nil,
        description: nil,
        members: [currentUser, dmProfile],
        otherMember: dmProfile,
        messages: [],
        isPinned: false,
        isUnread: false,
        isMuted: false,
        lastMessage: nil,
        imageURL: nil,
        isDraft: false
    )

    ConversationInfoView(conversation: dmConversation, messagingService: MockMessagingService())
}

#Preview("Group Conversation") {
    let members = [
        Profile(id: "user1", name: "Alice Johnson", username: "alice", avatar: nil),
        Profile(id: "user2", name: "Bob Smith", username: "bob", avatar: nil),
        Profile(id: "user3", name: "Charlie Brown", username: "charlie", avatar: nil),
        Profile(id: "user4", name: "Diana Prince", username: "diana", avatar: nil),
        Profile(id: "user5", name: "Eve Wilson", username: "eve", avatar: nil),
        Profile(id: "user6", name: "Frank Miller", username: "frank", avatar: nil),
        Profile(id: "user7", name: "Grace Lee", username: "grace", avatar: nil),
        Profile(id: "user8", name: "Henry Ford", username: "henry", avatar: nil),
        Profile(id: "user9", name: "Ivy Chen", username: "ivy", avatar: nil),
        Profile(id: "user10", name: "Jack Ryan", username: "jack", avatar: nil),
        Profile(id: "user11", name: "Kate Morgan", username: "kate", avatar: nil),
        Profile(id: "current", name: "Me", username: "me", avatar: nil)
    ]

    let groupConversation = Conversation(
        id: "group1",
        creator: members[0],
        createdAt: Date(),
        consent: .allowed,
        kind: .group,
        name: "The Conversation",
        description: "The official Ephemera hangout in Convos",
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

    ConversationInfoView(conversation: groupConversation, messagingService: MockMessagingService())
}
