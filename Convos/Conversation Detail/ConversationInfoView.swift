import SwiftUI

struct ConversationInfoView: View {
    @Bindable var viewModel: ConversationViewModel

    @Environment(\.dismiss) private var dismiss: DismissAction
    @State private var showingExplodeConfirmation: Bool = false

    private let maxMembersToShow: Int = 6
    private var displayedMembers: [ConversationMember] {
        let sortedMembers = viewModel.conversation.members.sortedByRole()
        return Array(sortedMembers.prefix(maxMembersToShow))
    }
    private var showViewAllMembers: Bool {
        viewModel.conversation.members.count > maxMembersToShow
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Spacer()
                        ImagePickerButton(
                            currentImage: $viewModel.conversationImage
                        )
                        .frame(width: 160.0, height: 160.0)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                .listSectionMargins(.top, 0.0)
                .listSectionSeparator(.hidden)

                Section {
                    TextField(viewModel.conversationNamePlaceholder, text: $viewModel.conversationName)
                        .textInputAutocapitalization(.words)
                        .lineLimit(1)
                    TextField(
                        viewModel.conversationDescriptionPlaceholder,
                        text: $viewModel.conversationDescription
                    )
                    .lineLimit(1)
                }

                Section("Invitations") {
                    Toggle(isOn: $viewModel.joinEnabled) {
                        Text("New people can join")
                    }
                    .disabled(true)

                    HStack {
                        VStack(alignment: .leading) {
                            Text(ConfigManager.shared.currentEnvironment.relyingPartyIdentifier)
                                .font(.caption)
                                .foregroundStyle(.colorTextSecondary)
                            Text(viewModel.invite.inviteUrlString)
                                .foregroundStyle(.colorTextPrimary)
                        }

                        Spacer()

                        ShareLink(item: viewModel.invite.inviteUrlString) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(.colorTextSecondary)
                        }
                    }

                    HStack {
                        Text("Maximum members")

                        Spacer()
                        Text("∞")
                            .foregroundStyle(.colorTextSecondary)
                    }
                    .opacity(0.5)
                    .disabled(true)
                }

                Section(viewModel.conversation.membersCountString) {
                    if viewModel.conversation.members.isEmpty {
                        Text("No one has joined yet")
                            .foregroundStyle(.colorTextSecondary)
                    } else {
                        ForEach(displayedMembers, id: \.id) { member in
                            NavigationLink {
                                ConversationMemberView(viewModel: viewModel, member: member)
                            } label: {
                                HStack {
                                    ProfileAvatarView(profile: member.profile)
                                        .frame(width: DesignConstants.ImageSizes.mediumAvatar, height: DesignConstants.ImageSizes.mediumAvatar)

                                    Text(member.profile.displayName)
                                        .font(.body)
                                }
                            }
                        }

                        if showViewAllMembers {
                            NavigationLink {
                                ConversationMembersListView(viewModel: viewModel)
                            } label: {
                                Text("View all")
                                    .foregroundStyle(.colorTextPrimary)
                            }
                        }
                    }
                }

                Section {
                    NavigationLink {
                        EmptyView()
                    } label: {
                        Text("Permissions")
                            .foregroundStyle(.colorTextPrimary)
                    }
                } footer: {
                    Text("Choose who can manage the group")
                        .foregroundStyle(.colorTextSecondary)
                }

                if viewModel.canRemoveMembers {
                    Section {
                        Button {
                            showingExplodeConfirmation = true
                        } label: {
                            Text("Explode now")
                                .foregroundStyle(.colorCaution)
                        }
                        .confirmationDialog("", isPresented: $showingExplodeConfirmation) {
                            Button("Explode", role: .destructive) {                           viewModel.explodeConvo()
                            }

                            Button("Cancel") {
                                showingExplodeConfirmation = false
                            }
                        }
                    } footer: {
                        Text("Irrecoverably delete the convo for everyone")
                            .foregroundStyle(.colorTextSecondary)
                    }
                }
            }
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .confirm) {
                        viewModel.onConversationSettingsDismissed()
                    }
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var viewModel: ConversationViewModel = .mock
    ConversationInfoView(viewModel: viewModel)
}
