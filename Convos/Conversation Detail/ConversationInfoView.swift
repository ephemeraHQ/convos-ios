import Combine
import SwiftUI

struct ConversationInfoView: View {
    let userState: UserState
    let conversationState: ConversationState
    let messagingService: any MessagingServiceProtocol
    @Environment(\.dismiss) private var dismiss: DismissAction
    @State private var showAllMembers: Bool = false
    @State private var showGroupEdit: Bool = false
    @State private var showAddMember: Bool = false

    private var conversation: Conversation? {
        conversationState.conversation
    }

    private var membersWithRoles: [ProfileWithRole] {
        conversationState.membersWithRoles
    }

    private var conversationWithAllMembers: Conversation? {
        guard let conversation = conversation else { return nil }
        // For group conversations, ensure current user is included in member list for proper display
        if conversation.kind == .group {
            return conversation.withCurrentUserIncluded()
        }
        return conversation
    }

    var body: some View {
        VStack(spacing: 0) {
            CustomToolbarView(onBack: { dismiss() }, rightContent: {
                if conversation?.kind == .group {
                    EditGroupButton(action: { showGroupEdit = true })
                }
            })

            // Content
            if let conversation = conversation {
                switch conversation.kind {
                case .dm:
                    DMInfoView(conversation: conversation)
                case .group:
                    if let conversationWithAllMembers = conversationWithAllMembers {
                        GroupInfoView(
                            conversation: conversationWithAllMembers,
                            userState: userState,
                            conversationState: conversationState,
                            messagingService: messagingService,
                            showAllMembers: $showAllMembers,
                            showAddMember: $showAddMember,
                            membersWithRoles: membersWithRoles
                        )
                    }
                }
            } else {
                // Loading state
                VStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $showAllMembers) {
            if let conversationWithAllMembers = conversationWithAllMembers {
                AllMembersView(
                    conversation: conversationWithAllMembers,
                    userState: userState,
                    conversationState: conversationState,
                    messagingService: messagingService,
                    membersWithRoles: membersWithRoles
                )
            }
        }
        .navigationDestination(isPresented: $showGroupEdit) {
            if let conversation = conversation {
                GroupEditView(conversation: conversation, messagingService: messagingService)
            }
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
                    VStack(spacing: DesignConstants.Spacing.step4x) {
                        ProfileAvatarView(profile: otherMember)
                            .frame(
                                width: DesignConstants.ImageSizes.largeAvatar,
                                height: DesignConstants.ImageSizes.largeAvatar
                            )

                        VStack(spacing: DesignConstants.Spacing.stepX) {
                            Text(otherMember.displayName)
                                .font(.title2)
                                .fontWeight(.semibold)

                            Text("@\(otherMember.username)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, DesignConstants.Spacing.step5x)
                }

                // Actions Section
                VStack(spacing: DesignConstants.Spacing.step3x) {
                    let action = {
                        // Handle message action
                    }
                    Button(action: action) {
                        HStack {
                            Image(systemName: "message.fill")
                                .foregroundColor(.primary)
                            Text("Message")
                                .foregroundColor(.primary)
                            Spacer()
                        }
                    }
                    .convosButtonStyle(.action())
                }
                .padding(.horizontal)

                // Settings Section
                VStack(alignment: .leading, spacing: DesignConstants.Spacing.step4x) {
                    Text("Settings")
                        .font(.headline)
                        .padding(.horizontal)

                    VStack(spacing: 0) {
                        SettingsRow(title: "Notifications", systemImage: "bell") {
                            // Handle notifications
                        }
                    }
                    .background(Color(.systemGray6))
                    .cornerRadius(DesignConstants.CornerRadius.small)
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
    let userState: UserState
    let conversationState: ConversationState
    let messagingService: any MessagingServiceProtocol
    @Binding var showAllMembers: Bool
    @Binding var showAddMember: Bool
    let membersWithRoles: [ProfileWithRole]
    @State private var showingAvailableSoonAlert: Bool = false
    @State private var showingAddMemberAlert: Bool = false

    private var currentUser: Profile? {
        userState.currentUser?.profile
    }

    private var displayedMembers: [ProfileWithRole] {
        let sortedMembers = membersWithRoles.sortedByRole(currentUser: currentUser)
        return Array(sortedMembers.prefix(6))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DesignConstants.Spacing.step6x) {
                // Group Header
                VStack(spacing: DesignConstants.Spacing.step4x) {
                    ConversationAvatarView(conversation: conversation)
                        .frame(
                            width: DesignConstants.ImageSizes.largeAvatar,
                            height: DesignConstants.ImageSizes.largeAvatar
                        )

                    VStack(spacing: DesignConstants.Spacing.stepX) {
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
                .padding(.top, DesignConstants.Spacing.step5x)

                // Members Section
                VStack(alignment: .leading, spacing: DesignConstants.Spacing.step4x) {
                    HStack {
                        Text("\(conversation.withCurrentUserIncluded().members.count) Members")
                            .font(.headline)
                        Spacer()
                        AddMemberButton(action: {
                            // @lourou add member to group
                            showingAddMemberAlert = true
                        })
                    }
                    .padding(.horizontal)

                    LazyVStack(spacing: 0) {
                        ForEach(displayedMembers, id: \.id) { memberWithRole in
                            MemberRowWithRole(
                                memberWithRole: memberWithRole,
                                conversationID: conversation.id,
                                messagingService: messagingService,
                                canDeleteMembers: true,
                                onMemberRemoved: { _ in
                                    // @lourou: Refresh conversation data
                                },
                                currentUser: currentUser
                            )

                            if memberWithRole.id != displayedMembers.last?.id {
                                Divider()
                                    .padding(.leading, DesignConstants.Spacing.step12x + DesignConstants.Spacing.step5x)
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
                    .cornerRadius(DesignConstants.CornerRadius.small)
                    .padding(.horizontal)
                }

                // Actions Section
                VStack(spacing: DesignConstants.Spacing.step3x) {
                    let action = {
                        showingAvailableSoonAlert = true
                    }
                    Button(action: action) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundColor(.red)
                            Text("Leave Group")
                                .foregroundColor(.red)
                            Spacer()
                        }
                    }
                    .convosButtonStyle(.action(isDestructive: true))
                }
                .padding(.horizontal)

                Spacer()
            }
        }
        .alert("Leave Group", isPresented: $showingAvailableSoonAlert, actions: {
            Button("OK") { }
        }, message: {
            Text("Available soon")
        })
        .alert("Add Member", isPresented: $showingAddMemberAlert, actions: {
            Button("OK") { }
        }, message: {
            Text("Available soon")
        })
    }
}

// MARK: - Supporting Views
struct SettingsRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundColor(.primary)
                    .frame(width: DesignConstants.Spacing.step5x)
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

struct MemberRowWithRole: View {
    let memberWithRole: ProfileWithRole
    let conversationID: String
    let messagingService: (any MessagingServiceProtocol)?
    let canDeleteMembers: Bool
    let onMemberRemoved: ((String) -> Void)?
    let currentUser: Profile?

    @State private var showingDeleteAlert: Bool = false
    @State private var isDeleting: Bool = false

    init(
        memberWithRole: ProfileWithRole,
        conversationID: String,
        messagingService: (any MessagingServiceProtocol)? = nil,
        canDeleteMembers: Bool = false,
        onMemberRemoved: ((String) -> Void)? = nil,
        currentUser: Profile? = nil) {
        self.memberWithRole = memberWithRole
        self.conversationID = conversationID
        self.messagingService = messagingService
        self.canDeleteMembers = canDeleteMembers
        self.onMemberRemoved = onMemberRemoved
        self.currentUser = currentUser
    }

    var body: some View {
        HStack {
            ProfileAvatarView(profile: memberWithRole.profile)
                .frame(width: DesignConstants.ImageSizes.mediumAvatar, height: DesignConstants.ImageSizes.mediumAvatar)

            VStack(alignment: .leading, spacing: DesignConstants.Spacing.stepHalf) {
                Text(memberWithRole.displayName)
                    .font(.body)
                    .fontWeight(.medium)

                Text("@\(memberWithRole.username)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !memberWithRole.role.displayName.isEmpty {
                Text(memberWithRole.role.displayName)
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(.horizontal, DesignConstants.Spacing.step2x)
                    .padding(.vertical, DesignConstants.Spacing.stepX)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(DesignConstants.CornerRadius.small)
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
        .alert("Remove Member", isPresented: $showingDeleteAlert, actions: {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                Task {
                    await removeMember()
                }
            }
        }, message: {
            Text("Are you sure you want to remove \(memberWithRole.displayName) from this group?")
        })
    }

    private var isCurrentUser: Bool {
        // Check if this member is the current user by comparing IDs
        guard let currentUser = currentUser else { return false }
        return memberWithRole.id == currentUser.id
    }

    private func removeMember() async {
        guard let messagingService = messagingService else { return }

        isDeleting = true

        do {
            let metadataWriter = messagingService.groupMetadataWriter()
            try await metadataWriter.removeGroupMembers(
                groupId: conversationID,
                memberInboxIds: [memberWithRole.id]
            )
            await MainActor.run {
                onMemberRemoved?(memberWithRole.id)
                isDeleting = false
            }
        } catch {
            await MainActor.run {
                // @lourou: Show error alert
                Logger.error("Failed to remove member \(memberWithRole.id): \(error)")
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
                .font(DesignConstants.Fonts.standard)
                .foregroundColor(.primary)
                .padding(.vertical, DesignConstants.Spacing.step2x)
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
    let userState: UserState
    let conversationState: ConversationState
    let messagingService: any MessagingServiceProtocol
    @Environment(\.dismiss) private var dismiss: DismissAction
    @State private var showAddMember: Bool = false
    let membersWithRoles: [ProfileWithRole]
    @State private var showingAddMemberAlert: Bool = false

    private var currentUser: Profile? {
        userState.currentUser?.profile
    }

    private var sortedMembers: [ProfileWithRole] {
        return membersWithRoles.sortedByRole(currentUser: currentUser)
    }

    var body: some View {
        VStack(spacing: 0) {
            CustomToolbarView(onBack: { dismiss() }, rightContent: {
                AddMemberButton(action: {
                    // @lourou add member to group
                    showingAddMemberAlert = true
                })
            })

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sortedMembers, id: \.id) { memberWithRole in
                        MemberRowWithRole(
                            memberWithRole: memberWithRole,
                            conversationID: conversation.id,
                            messagingService: messagingService,
                            canDeleteMembers: true,
                            onMemberRemoved: { _ in
                                // @lourou: Refresh conversation data
                            },
                            currentUser: currentUser
                        )

                        if memberWithRole.id != sortedMembers.last?.id {
                            Divider()
                                .padding(.leading, DesignConstants.Spacing.step12x + DesignConstants.Spacing.step5x)
                        }
                    }
                }
                .background(Color(.systemGray6))
                .cornerRadius(DesignConstants.CornerRadius.small)
                .padding()
            }
        }
        .navigationBarHidden(true)
        // @lourou add member to group
        // .navigationDestination(isPresented: $showAddMember) {
        //     AddMemberView(conversation: conversation, messagingService: messagingService)
        // }
        .alert("Add Member", isPresented: $showingAddMemberAlert, actions: {
            Button("OK") { }
        }, message: {
            Text("Available soon")
        })
    }
}

#Preview("DM Conversation") {
    @Previewable @State var userState: UserState = .init(userRepository: MockUserRepository())
    @Previewable @State var conversationState: ConversationState = .init(
        conversationRepository: MockMessagingService().conversationRepository(for: "dm1")
    )

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

    let mockMessagingService = MockMessagingService()

    ConversationInfoView(
        userState: userState,
        conversationState: conversationState,
        messagingService: mockMessagingService
    )
}

#Preview("Group Conversation") {
    @Previewable @State var userState: UserState = .init(userRepository: MockUserRepository())
    @Previewable @State var conversationState: ConversationState = .init(
        conversationRepository: MockMessagingService().conversationRepository(for: "group1")
    )

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

    let mockMessagingService = MockMessagingService()

    ConversationInfoView(
        userState: userState,
        conversationState: conversationState,
        messagingService: mockMessagingService
    )
}
