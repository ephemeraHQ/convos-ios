import Combine
import SwiftUI

struct ConversationInfoView: View {
    let conversation: Conversation
    let groupMetadataWriter: any GroupMetadataWriterProtocol
    @State private var showAllMembersForConversation: Conversation?
    @State private var showGroupEditForConversation: Conversation?
    @State private var showAddMember: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            switch conversation.kind {
            case .dm:
                DMInfoView(conversation: conversation)
            case .group:
                GroupInfoView(
                    conversation: conversation,
                    groupMetadataWriter: groupMetadataWriter,
                    showAllMembersForConversation: $showAllMembersForConversation,
                    showAddMember: $showAddMember
                )
            }
        }
        .navigationDestination(item: $showAllMembersForConversation) { conversation in
            AllMembersView(
                conversation: conversation,
                groupMetadataWriter: groupMetadataWriter
            )
        }
        .navigationDestination(item: $showGroupEditForConversation) { conversation in
            GroupEditView(
                conversation: conversation,
                groupMetadataWriter: groupMetadataWriter
            )
        }
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if conversation.kind == .group {
                    EditGroupButton {
                        showGroupEditForConversation = conversation
                    }
                }
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
                        ProfileAvatarView(profile: otherMember.profile)
                            .frame(
                                width: DesignConstants.ImageSizes.largeAvatar,
                                height: DesignConstants.ImageSizes.largeAvatar
                            )

                        VStack(spacing: DesignConstants.Spacing.stepX) {
                            Text(otherMember.profile.displayName)
                                .font(.title2)
                                .fontWeight(.semibold)

                            if let username = otherMember.profile.username {
                                Text("@\(username)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
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
    let groupMetadataWriter: any GroupMetadataWriterProtocol
    @Binding var showAllMembersForConversation: Conversation?
    @Binding var showAddMember: Bool
    @State private var showingAvailableSoonAlert: Bool = false
    @State private var showingAddMemberAlert: Bool = false

    private var displayedMembers: [ConversationMember] {
        let sortedMembers = conversation.members.sortedByRole()
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
                        Text("\(conversation.members.count) Members")
                            .font(.headline)
                        Spacer()
                        AddMemberButton(action: {
                            // @lourou add member to group
                            showingAddMemberAlert = true
                        })
                    }
                    .padding(.horizontal)

                    LazyVStack(spacing: 0) {
                        ForEach(displayedMembers, id: \.id) { member in
                            ConversationMemberRow(
                                member: member,
                                conversationID: conversation.id,
                                groupMetadataWriter: groupMetadataWriter,
                                canDeleteMembers: true,
                                onMemberRemoved: { _ in
                                    // @lourou: Refresh conversation data
                                }
                            )

                            if member.id != displayedMembers.last?.id {
                                Divider()
                                    .padding(.leading, DesignConstants.Spacing.step12x + DesignConstants.Spacing.step5x)
                            }
                        }

                        if conversation.members.count > 6 {
                            SeeAllMembersButton(
                                memberCount: conversation.members.count,
                                action: { showAllMembersForConversation = conversation }
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

struct ConversationMemberRow: View {
    let member: ConversationMember
    let conversationID: String
    let groupMetadataWriter: any GroupMetadataWriterProtocol
    let canDeleteMembers: Bool
    let onMemberRemoved: ((String) -> Void)?

    @State private var showingDeleteAlert: Bool = false
    @State private var isDeleting: Bool = false

    init(
        member: ConversationMember,
        conversationID: String,
        groupMetadataWriter: any GroupMetadataWriterProtocol,
        canDeleteMembers: Bool = false,
        onMemberRemoved: ((String) -> Void)? = nil) {
            self.member = member
            self.conversationID = conversationID
            self.groupMetadataWriter = groupMetadataWriter
            self.canDeleteMembers = canDeleteMembers
            self.onMemberRemoved = onMemberRemoved
        }

    var body: some View {
        HStack {
            ProfileAvatarView(profile: member.profile)
                .frame(width: DesignConstants.ImageSizes.mediumAvatar, height: DesignConstants.ImageSizes.mediumAvatar)

            VStack(alignment: .leading, spacing: DesignConstants.Spacing.stepHalf) {
                Text(member.profile.displayName)
                    .font(.body)
                    .fontWeight(.medium)

                Text("@\(member.profile.username)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !member.role.displayName.isEmpty {
                Text(member.role.displayName)
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(.horizontal, DesignConstants.Spacing.step2x)
                    .padding(.vertical, DesignConstants.Spacing.stepX)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(DesignConstants.CornerRadius.small)
            }

            if canDeleteMembers && !member.isCurrentUser {
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
            Text("Are you sure you want to remove \(member.profile.displayName) from this group?")
        })
    }

    private func removeMember() async {
        isDeleting = true

        do {
            try await groupMetadataWriter.removeGroupMembers(
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
    let groupMetadataWriter: any GroupMetadataWriterProtocol
    @Environment(\.dismiss) private var dismiss: DismissAction
    @State private var showAddMember: Bool = false
    @State private var showingAddMemberAlert: Bool = false

    private var sortedMembers: [ConversationMember] {
        conversation.members.sortedByRole()
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sortedMembers, id: \.id) { member in
                        ConversationMemberRow(
                            member: member,
                            conversationID: conversation.id,
                            groupMetadataWriter: groupMetadataWriter,
                            canDeleteMembers: true,
                            onMemberRemoved: { _ in
                                // @lourou: Refresh conversation data
                            }
                        )

                        if member.id != sortedMembers.last?.id {
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
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Text("Back")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                AddMemberButton {
                    // @lourou add member to group
                    showingAddMemberAlert = true
                }
            }
        }
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
    ConversationInfoView(
        conversation: .mock(),
        groupMetadataWriter: MockGroupMetadataWriter()
    )
}

#Preview("Group Conversation") {
    ConversationInfoView(
        conversation: .mock(),
        groupMetadataWriter: MockGroupMetadataWriter()
    )
}
