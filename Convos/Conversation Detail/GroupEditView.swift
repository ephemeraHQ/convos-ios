import PhotosUI
import SwiftUI

struct GroupEditView: View {
    let conversation: Conversation
    let groupMetadataWriter: any GroupMetadataWriterProtocol
    @Environment(\.dismiss) private var dismiss: DismissAction

    @State private var editState: GroupEditState
    @FocusState private var isDescriptionFocused: Bool

    init(conversation: Conversation, groupMetadataWriter: any GroupMetadataWriterProtocol) {
        self.conversation = conversation
        self.groupMetadataWriter = groupMetadataWriter
        self._editState = State(initialValue: GroupEditState(
            conversation: conversation,
            groupMetadataWriter: groupMetadataWriter
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scrollProxy in
                Form {
                    Section {
//                        groupImageSection
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // Mark changes as saved to prevent revert on dismiss
                    editState.markChangesSaved()

                    // Dismiss immediately for instant UI (optimistic)
                    dismiss()

                    // Save in background
                    Task {
//                        await editState.saveGroupChanges()
                    }
                } label: {
                    Text("Done")
                        .foregroundColor(.blue)
                        .font(.system(size: 16, weight: .medium))
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
        .cachedImage(for: conversation) { _ in
            editState.onImageCacheUpdate()
        }
        .alert("Group Update", isPresented: $editState.showingAlert) {
            Button("OK") { }
        } message: {
            Text(editState.alertMessage)
        }
    }

//    private var groupImageSection: some View {
//        HStack {
//            Spacer()
//            PhotosPicker(selection: $editState.imageSelection,
//                         matching: .images,
//                         photoLibrary: .shared()) {
//                ZStack {
//                    switch editState.imageState {
//                    case .loading:
//                        ProgressView()
//                            .frame(width: 120, height: 120)
//                    case .failure:
//                        VStack {
//                            Image(systemName: "exclamationmark.triangle")
//                                .foregroundColor(.red)
//                            Text("Error loading image")
//                                .font(.caption)
//                                .foregroundColor(.red)
//                        }
//                        .frame(width: 120, height: 120)
//                    case .empty:
//                        if let currentConversationImage = editState.currentConversationImage {
//                            Image(uiImage: currentConversationImage)
//                                .resizable()
//                                .aspectRatio(contentMode: .fill)
//                                .frame(width: 120, height: 120)
//                                .clipShape(Circle())
//                        } else {
//                            AvatarView(
//                                imageURL: conversation.imageURL,
//                                fallbackName: conversation.name ?? "Group",
//                                cacheableObject: conversation
//                            )
//                            .frame(width: 120, height: 120)
//                        }
//                    case let .success(image):
//                        Image(uiImage: image)
//                            .resizable()
//                            .aspectRatio(contentMode: .fill)
//                            .frame(width: 120, height: 120)
//                            .clipShape(Circle())
//                    }
//
//                    VStack {
//                        Spacer()
//                        HStack {
//                            Spacer()
//                            ZStack {
//                                Circle()
//                                    .fill(.brown)
//                                    .frame(width: 32, height: 32)
//                                Image(systemName: "camera.fill")
//                                    .foregroundColor(.white)
//                                    .font(.system(size: 16))
//                            }
//                        }
//                    }
//                    .frame(width: 120, height: 120)
//                }
//            }
//            .buttonStyle(.borderless)
//            Spacer()
//        }
//        .padding(.vertical, 8)
//    }

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
        ConversationMember.mock(name: "Alice"),
        ConversationMember.mock(name: "Bobe"),
        ConversationMember.mock(name: "Me")
    ]

    let groupConversation = Conversation(
        id: "group1",
        inboxId: UUID().uuidString,
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
        isDraft: false,
        invite: .mock()
    )

    GroupEditView(
        conversation: groupConversation,
        groupMetadataWriter: MockGroupMetadataWriter()
    )
}
