import PhotosUI
import SwiftUI

struct GroupImage: Transferable {
    enum State {
        case loading, empty, success(Image), failure(Error)
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

    let image: Image

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            #if canImport(AppKit)
                guard let nsImage = NSImage(data: data) else {
                    throw GroupImageError.importFailed
                }
                let image = Image(nsImage: nsImage)
                return GroupImage(image: image)
            #elseif canImport(UIKit)
                guard let uiImage = UIImage(data: data) else {
                    throw GroupImageError.importFailed
                }
                let image = Image(uiImage: uiImage)
                return GroupImage(image: image)
            #else
                throw GroupImageError.importFailed
            #endif
        }
    }
}

extension PhotosPickerItem {
    @MainActor
    func loadGroupImage() async -> GroupImage.State {
        do {
            if let groupImage = try await loadTransferable(type: GroupImage.self) {
                return .success(groupImage.image)
            } else {
                return .empty
            }
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
    @State private var imageState: GroupImage.State = .empty
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
                    let imageState = await imageSelection.loadGroupImage()
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
                        MonogramView(name: conversation.name ?? "Group")
                            .frame(width: 120, height: 120)
                    case let .success(image):
                        image
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

        // Check if image changed (new image selected)
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
        // Use real XMTP metadata writer
        let metadataWriter = messagingService.groupMetadataWriter()
        try await metadataWriter.updateGroupName(groupId: conversation.id, name: groupName)

        Logger.info("Successfully updated group name to: \(groupName)")
    }

    private func updateGroupDescription() async throws {
        // Use real XMTP metadata writer
        let metadataWriter = messagingService.groupMetadataWriter()
        try await metadataWriter.updateGroupDescription(groupId: conversation.id, description: groupDescription)

        Logger.info("Successfully updated group description to: \(groupDescription)")
    }

    private func updateGroupImage(imageURL: String) async throws {
        // Use real XMTP metadata writer
        let metadataWriter = messagingService.groupMetadataWriter()
        try await metadataWriter.updateGroupImageUrl(groupId: conversation.id, imageUrl: imageURL)

        Logger.info("Successfully updated group image to: \(imageURL)")
    }

    private func uploadImage() async throws -> String {
        guard case .success(let image) = imageState else {
            throw GroupImage.GroupImageError.importFailed
        }

        Logger.info("Uploading group image...")

        // Convert SwiftUI Image to UIImage
        guard let uiImage = image.asUIImage() else {
            Logger.error("Failed to convert SwiftUI Image to UIImage")
            throw GroupImage.GroupImageError.importFailed
        }

        let estimatedBytes = Int(uiImage.size.width * uiImage.size.height * 4)
        Logger.info("Original image size: \(uiImage.size), estimated bytes: \(estimatedBytes)")

        // Compress and resize image to max 1024x1024 while maintaining aspect ratio
        guard let compressedImageData = ImageCompression.compressImage(uiImage, maxDimension: 1024, quality: 0.8) else {
            Logger.error("Failed to compress image")
            throw GroupImage.GroupImageError.importFailed
        }

        Logger.info("Compressed image data size: \(ImageCompression.formatFileSize(compressedImageData.count))")

        // Use the messaging service's authenticated upload method
        let imageURL = try await messagingService.uploadImage(data: compressedImageData, filename: "group-image.jpg")

        Logger.info("Successfully uploaded image to: \(imageURL)")
        return imageURL
    }

    private func uploadImageAndUpdateProfile() async throws {
        guard case .success(let image) = imageState else {
            throw GroupImage.GroupImageError.importFailed
        }

        Logger.info("Starting chained image upload and profile update...")

        // Convert SwiftUI Image to UIImage
        guard let uiImage = image.asUIImage() else {
            Logger.error("Failed to convert SwiftUI Image to UIImage")
            throw GroupImage.GroupImageError.importFailed
        }

        let estimatedBytes = Int(uiImage.size.width * uiImage.size.height * 4)
        Logger.info("Original image size: \(uiImage.size), estimated bytes: \(estimatedBytes)")

        // Compress and resize image to max 1024x1024 while maintaining aspect ratio
        guard let compressedImageData = ImageCompression.compressImage(uiImage, maxDimension: 1024, quality: 0.8) else {
            Logger.error("Failed to compress image")
            throw GroupImage.GroupImageError.importFailed
        }

        Logger.info("Compressed image data size: \(ImageCompression.formatFileSize(compressedImageData.count))")

        // Use the chained upload method that ensures profile update happens after upload
        let imageURL = try await messagingService.uploadImageAndExecute(
            data: compressedImageData,
            filename: "group-image.jpg"
        ) { uploadedURL in
            // This closure runs AFTER the upload is complete
            Logger.info("Upload completed successfully, updating group image with URL: \(uploadedURL)")
            try await self.updateGroupImage(imageURL: uploadedURL)
        }

        Logger.info("Successfully completed chained upload and profile update: \(imageURL)")
    }
}

// MARK: - Helper Extensions

extension Image {
    func asUIImage() -> UIImage? {
        // Use a flexible container that maintains aspect ratio
        let imageView = self
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: 1024, maxHeight: 1024)

        let controller = UIHostingController(rootView: imageView)
        let view = controller.view

        // Let SwiftUI determine the natural size to preserve aspect ratio
        let targetSize = controller.sizeThatFits(in: CGSize(width: 1024, height: 1024))
        view?.bounds = CGRect(origin: .zero, size: targetSize)
        view?.backgroundColor = .clear

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            view?.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
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

    GroupEditView(conversation: groupConversation, messagingService: MockMessagingService())
}
