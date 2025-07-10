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

    @State private var groupName: String
    @State private var groupDescription: String
    @State private var uniqueLink: String
    @State private var imageState: GroupImageState = .empty

    @State private var imageSelection: PhotosPickerItem?
    @State private var showingAlert: Bool = false
    @State private var alertMessage: String = ""

    @FocusState private var isDescriptionFocused: Bool

    private let nameCharacterLimit: Int = 100
    private let descriptionCharacterLimit: Int = 300

//    @lourou: Replace with actual current user ID
//    private let currentUserID = "current"

    private var canEditGroup: Bool {
//         @lourou: Use real permissions check from messaging service
//         Task {
//             let permissionsRepo = messagingService.groupPermissionsRepository()
//             let canUpdateName = try await permissionsRepo.canPerformAction(
//                memberInboxId: currentUserID,
//                action: .updateGroupName,
//                in: conversation.id)
//             let canUpdateDescription = try await permissionsRepo.canPerformAction(
//                memberInboxId: currentUserID,
//                action: .updateGroupDescription,
//                in: conversation.id)
//             let canUpdateImage = try await permissionsRepo.canPerformAction(
//                memberInboxId: currentUserID,
//                action: .updateGroupImage,
//                in: conversation.id)
//             return canUpdateName || canUpdateDescription || canUpdateImage
//         }
        // For now, allow editing for demo purposes (this should be async in a real implementation)
        return true
    }

    init(conversation: Conversation, messagingService: any MessagingServiceProtocol) {
        self.conversation = conversation
        self.messagingService = messagingService
        self._groupName = State(initialValue: conversation.name ?? "")
        self._groupDescription = State(initialValue: conversation.description ?? "")
        self._uniqueLink = State(initialValue: "convosation")
    }

    var body: some View {
        VStack(spacing: 0) {
            CustomToolbarView(onBack: { dismiss() }, rightContent: {
                let action = {
                    Task {
                        await saveGroupChanges()
                    }
                    return ()
                }
                Button(action: action) {
                    Text("Done")
                        .foregroundColor(.blue)
                        .font(.system(size: 16, weight: .medium))
                }
                .padding(.vertical, 10.0)
                .padding(.horizontal, DesignConstants.Spacing.step2x)
                .disabled(!canEditGroup)
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
        .alert("Group Update", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .onChange(of: imageSelection) {
            if let imageSelection {
                self.imageState = .loading
                Task {
                    let imageState = await imageSelection.loadImage()
                    withAnimation {
                        self.imageState = imageState
                        // Image loaded successfully - actual upload will happen when user saves
                        if case .success = imageState {
                            Logger.info("Group image loaded successfully and ready for upload")
                        }
                    }
                }
            }
        }
    }

    private var groupImageSection: some View {
        HStack {
            Spacer()
            PhotosPicker(selection: $imageSelection,
                         matching: .images,
                         photoLibrary: .shared()) {
                ZStack {
                    switch imageState {
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
                        // Use AvatarView directly - it handles caching and eliminates flicker
                        AvatarView(imageURL: conversation.imageURL,
                                  fallbackName: conversation.name ?? "Group")
                            .frame(width: 120, height: 120)
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

            TextField("Group name", text: $groupName)
                .textFieldStyle(.plain)
                .font(.body)
                .autocorrectionDisabled()
                .onChange(of: groupName) { _, newValue in
                    if newValue.count > nameCharacterLimit {
                        groupName = String(newValue.prefix(nameCharacterLimit))
                    }
                }

            if groupName.count > nameCharacterLimit - 20 {
                HStack {
                    Spacer()
                    Text("\(groupName.count)/\(nameCharacterLimit)")
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
                text: $groupDescription,
                axis: .vertical
            )
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(1...10)
                .autocorrectionDisabled()
                .focused($isDescriptionFocused)
                .onChange(of: groupDescription) { _, newValue in
                    if newValue.count > descriptionCharacterLimit {
                        groupDescription = String(newValue.prefix(descriptionCharacterLimit))
                    }
                }

            if groupDescription.count > descriptionCharacterLimit - 50 {
                HStack {
                    Spacer()
                    Text("\(groupDescription.count)/\(descriptionCharacterLimit)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize()
                }
            }
        }
    }

    private var uniqueLinkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("convos.org/group/")
                    .foregroundColor(.secondary)
                TextField("convosation", text: $uniqueLink)
                    .textFieldStyle(.plain)
                let copyAction = { /* @lourou: Implement copy functionality */ }
                Button(action: copyAction) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)

            Text("Your unique sharable link")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func saveGroupChanges() async {
        var hasChanges = false

        // Check if name changed
        if groupName != conversation.name {
            hasChanges = true
        }

        // Check if description changed
        if groupDescription != conversation.description {
            hasChanges = true
        }

        // Check if image changed (new image selected or current image cleared)
        if case .success = imageState {
            hasChanges = true
        }

        if hasChanges {
            // Dismiss immediately (optimistic)
            await MainActor.run {
                dismiss()
            }

            // Update in background
            do {
                if groupName != conversation.name {
                    try await updateGroupName()
                }

                if groupDescription != conversation.description {
                    try await updateGroupDescription()
                }

                // Handle image upload and update chained together
                if case .success = imageState {
                    try await uploadImageAndUpdateProfile()
                }
            } catch {
                Logger.error("Failed to update group: \(error)")
                await MainActor.run {
                    alertMessage = "Group update failed: \(error.localizedDescription)"
                    showingAlert = true
                }
            }
        } else {
            // No changes, just dismiss
            await MainActor.run {
                dismiss()
            }
        }
    }

    private func updateGroupName() async throws {
        let metadataWriter = messagingService.groupMetadataWriter()
        try await metadataWriter.updateGroupName(groupId: conversation.id, name: groupName)

        Logger.info("Successfully updated group name to: \(groupName)")
    }

    private func updateGroupDescription() async throws {
        let metadataWriter = messagingService.groupMetadataWriter()
        try await metadataWriter.updateGroupDescription(groupId: conversation.id, description: groupDescription)

        Logger.info("Successfully updated group description to: \(groupDescription)")
    }

    private func updateGroupImage(imageURL: String) async throws {
        let metadataWriter = messagingService.groupMetadataWriter()
        try await metadataWriter.updateGroupImageUrl(groupId: conversation.id, imageUrl: imageURL)

        Logger.info("Successfully updated group image to: \(imageURL)")
    }



    private func prepareImageForUpload() async throws -> Data {
        guard case .success(let image) = imageState else {
            throw GroupImageError.importFailed
        }

        Logger.info("Preparing group image for upload...")

        let estimatedBytes = Int(image.size.width * image.size.height * 4)
        Logger.info("Original image size: \(image.size), estimated bytes: \(estimatedBytes)")

        // Compress and resize image to max 1024x1024 while maintaining aspect ratio
        guard let compressedImageData = ImageCompression.compressImage(image, maxDimension: 1024, quality: 0.8) else {
            Logger.error("Failed to compress image")
            throw GroupImageError.importFailed
        }

        Logger.info("Compressed image data size: \(ImageCompression.formatFileSize(compressedImageData.count))")
        return compressedImageData
    }

        private func uploadImageAndUpdateProfile() async throws {
        Logger.info("Starting chained image upload and profile update...")

        let compressedImageData = try await prepareImageForUpload()

        // Generate unique filename to avoid collisions
        let filename = "group-image-\(UUID().uuidString).jpg"

        // Use the chained upload method that ensures profile update happens after upload
        let imageURL = try await messagingService.uploadImageAndExecute(
            data: compressedImageData,
            filename: filename
        ) { uploadedURL in
            // This closure runs after the upload is complete
            Logger.info("Upload completed successfully, updating group image with URL: \(uploadedURL)")
            try await self.updateGroupImage(imageURL: uploadedURL)
        }

        Logger.info("Successfully completed chained upload and profile update: \(imageURL)")
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

    GroupEditView(conversation: groupConversation, messagingService: MockMessagingService())
}
