import PhotosUI
import SwiftUI

enum GroupImageState {
    case loading, empty, success(UIImage), failure(Error)

    var isEmpty: Bool {
        if case .empty = self {
            return true
        }
        return false
    }
}

enum GroupImageError: Error {
    case importFailed
}

extension PhotosPickerItem {
    @MainActor
    func loadImage() async -> GroupImageState {
        do {
            guard let data = try await loadTransferable(type: Data.self) else {
                return .empty
            }

            guard let image = UIImage(data: data) else {
                return .failure(GroupImageError.importFailed)
            }

            return .success(image)
        } catch {
            return .failure(error)
        }
    }
}

struct GroupEditView: View {
    let conversation: Conversation
    let messagingService: any MessagingServiceProtocol
    @Environment(\.dismiss) private var dismiss: DismissAction

    @State private var editState: GroupEditState
    @FocusState private var isDescriptionFocused: Bool

    init(conversation: Conversation, messagingService: any MessagingServiceProtocol) {
        self.conversation = conversation
        self.messagingService = messagingService
        self._editState = State(initialValue: GroupEditState(
            conversation: conversation,
            messagingService: messagingService
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            CustomToolbarView(onBack: { dismiss() }, rightContent: {
                let action = {
                    // Mark changes as saved to prevent revert on dismiss
                    editState.markChangesSaved()

                    // Dismiss immediately for instant UI (optimistic)
                    dismiss()

                    // Save in background
                    Task {
                        await editState.saveGroupChanges()
                    }
                }
                Button(action: action) {
                    Text("Done")
                        .foregroundColor(.blue)
                        .font(.system(size: 16, weight: .medium))
                }
                .padding(.vertical, 10.0)
                .padding(.horizontal, DesignConstants.Spacing.step2x)
                .disabled(!editState.canEditGroup)
            })

            ScrollViewReader { scrollProxy in
                Form {
                    Section {
                        groupImageSection
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    Section("Group Info") {
                        groupNameField
                        groupDescriptionField
                            .id("descriptionField")
                            .onTapGesture {
                                // Keep focus when tapping description field
                            }
                    }
                }
                .scrollDismissesKeyboard(.never)
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo("descriptionField", anchor: .center)
                        }
                    }
                }
                .onChange(of: isDescriptionFocused) { _, focused in
                    if focused {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                scrollProxy.scrollTo("descriptionField", anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            editState.onAppear()
        }
        .onDisappear {
            editState.onDisappear()
        }
        .onChange(of: ImageCache.shared.lastUpdateTime) { _, _ in
            editState.onImageCacheUpdate()
        }
        .alert("Group Update", isPresented: $editState.showingAlert) {
            Button("OK") { }
        } message: {
            Text(editState.alertMessage)
        }
    }

    private var groupImageSection: some View {
        HStack {
            Spacer()
            PhotosPicker(selection: $editState.imageSelection,
                         matching: .images,
                         photoLibrary: .shared()) {
                ZStack {
                    switch editState.imageState {
                    case .loading:
                        ProgressView()
                            .frame(width: 120, height: 120)
                    case .failure:
                        VStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.red)
                            Text("Error loading image")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .frame(width: 120, height: 120)
                    case .empty:
                        if let currentConversationImage = editState.currentConversationImage {
                            Image(uiImage: currentConversationImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 120, height: 120)
                                .clipShape(Circle())
                        } else {
                            AvatarView(imageURL: conversation.imageURL,
                                       fallbackName: conversation.name ?? "Group",
                                       conversationId: conversation.id)
                                .frame(width: 120, height: 120)
                        }
                    case let .success(image):
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                    }

                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(.brown)
                                    .frame(width: 32, height: 32)
                                Image(systemName: "camera.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 16))
                            }
                        }
                    }
                    .frame(width: 120, height: 120)
                }
            }
            .buttonStyle(.borderless)
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var groupNameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .font(.subheadline)
                .foregroundColor(.secondary)

            TextField("Group name", text: $editState.groupName)
                .textFieldStyle(.plain)
                .font(.body)
                .autocorrectionDisabled()

            if editState.shouldShowNameCharacterCount {
                HStack {
                    Spacer()
                    Text("\(editState.groupName.count)/\(editState.nameCharacterLimit)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize()
                }
            }
        }
    }

    private var groupDescriptionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description")
                .font(.subheadline)
                .foregroundColor(.secondary)

            TextField(
                "Add a description for your group",
                text: $editState.groupDescription,
                axis: .vertical
            )
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(1...10)
                .autocorrectionDisabled()
                .focused($isDescriptionFocused)

            if editState.shouldShowDescriptionCharacterCount {
                HStack {
                    Spacer()
                    Text("\(editState.groupDescription.count)/\(editState.descriptionCharacterLimit)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize()
                }
            }
        }
    }
}

#Preview {
    let members = [
        Profile(id: "user1", name: "Alice Johnson", username: "alice", avatar: nil),
        Profile(id: "user2", name: "Bob Smith", username: "bob", avatar: nil),
        Profile(id: "current", name: "Me", username: "me", avatar: nil)
    ]

    let groupConversation = Conversation(
        id: "group1",
        creator: members[0],
        createdAt: Date(),
        consent: .allowed,
        kind: .group,
        name: "Convos Crew",
        description: "Working towards the Bedrock milestone: world-class messaging on tomorrow's " +
                     "foundations (well underway)",
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

    GroupEditView(
        conversation: groupConversation,
        messagingService: MockMessagingService()
    )
}
