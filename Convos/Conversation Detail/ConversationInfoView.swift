import SwiftUI

struct ConversationInfoView: View {
    let conversation: Conversation
    @Environment(\.dismiss) private var dismiss: DismissAction
    @State private var showAllMembers: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            CustomToolbarView(onBack: { dismiss() }, rightContent: {
                if conversation.kind == .group {
                    EditGroupButton(action: {})
                }
            })

            // Content
            switch conversation.kind {
            case .dm:
                DMInfoView(conversation: conversation)
            case .group:
                GroupInfoView(conversation: conversation, showAllMembers: $showAllMembers)
            }
        }
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $showAllMembers) {
            AllMembersView(conversation: conversation)
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
    @Binding var showAllMembers: Bool

    private var displayedMembers: [Profile] {
        Array(conversation.members.prefix(6))
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
                        Text("\(conversation.members.count) Members")
                            .font(.headline)
                        Spacer()
                        AddMemberButton(action: {})
                    }
                    .padding(.horizontal)

                    LazyVStack(spacing: 0) {
                        ForEach(displayedMembers, id: \.id) { member in
                            MemberRow(member: member)

                            if member.id != displayedMembers.last?.id {
                                Divider()
                                    .padding(.leading, 60)
                            }
                        }

                        if conversation.members.count > 6 {
                            SeeAllMembersButton(
                                memberCount: conversation.members.count,
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
        }
        .padding()
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
                .foregroundColor(.primary)
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
    @Environment(\.dismiss) private var dismiss: DismissAction

    var body: some View {
        VStack(spacing: 0) {
            CustomToolbarView(onBack: { dismiss() }, rightContent: {
                AddMemberButton(action: {})
            })

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(conversation.members, id: \.id) { member in
                        MemberRow(member: member)

                        if member.id != conversation.members.last?.id {
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

    ConversationInfoView(conversation: dmConversation)
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
        Profile(id: "user12", name: "Liam O'Connor", username: "liam", avatar: nil),
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

    ConversationInfoView(conversation: groupConversation)
}
