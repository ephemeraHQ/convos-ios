import SwiftUI

struct ConversationInfoView: View {
    let conversation: Conversation
    @Environment(\.dismiss) private var dismiss: DismissAction

    var body: some View {
        VStack(spacing: 0) {
            CustomToolbarView(onBack: { dismiss() }, rightContent: {
                // Add right-side buttons here
            })

            // Content
            switch conversation.kind {
            case .dm:
                DMInfoView(conversation: conversation)
            case .group:
                GroupInfoView(conversation: conversation)
            }
        }
        .navigationBarHidden(true)
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

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Group Header
                VStack(spacing: 16) {
                    ConversationAvatarView(conversation: conversation)

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
                        Text("Members")
                            .font(.headline)
                        Spacer()
                        Button("Add") {
                            // Handle add member
                        }
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    }
                    .padding(.horizontal)

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
                    .padding(.horizontal)
                }

                // Actions Section
                VStack(spacing: 12) {
                    GroupActionButton(title: "Edit Group", systemImage: "pencil") {
                        // Handle edit group
                    }

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
                    .foregroundColor(.blue)
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
