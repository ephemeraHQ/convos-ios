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
    @State private var requireAdminApproval: Bool = false
    @State private var imageState: GroupImage.State = .empty
    @State private var imageSelection: PhotosPickerItem?
    @State private var isSaving: Bool = false
    @State private var showingAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var uploadedImageURL: String?

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
                Button("Done") {
                    Task {
                        await saveGroupChanges()
                    }
                }
                .foregroundColor(isSaving ? .gray : .blue)
                .font(.system(size: 16, weight: .medium))
                .disabled(isSaving || !canEditGroup)
            })

            ScrollView {
                VStack(spacing: 24) {
                    groupImageSection

                    VStack(spacing: 16) {
                        groupNameSection
                        groupDescriptionSection
                        uniqueLinkSection
                        adminApprovalSection
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 20)
            }
            .disabled(isSaving)
            .overlay(
                isSaving ? Color.black.opacity(0.3) : Color.clear
            )
            .overlay(
                isSaving ? ProgressView("Saving...")
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
                    .shadow(radius: 10) : nil
            )
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
                        // Upload image when selected
                        if case .success = imageState {
                            Task {
                                do {
                                    let url = try await uploadImage()
                                    uploadedImageURL = url
                                } catch {
                                    alertMessage = "Failed to upload image"
                                    showingAlert = true
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var groupImageSection: some View {
        VStack(spacing: 16) {
            PhotosPicker(selection: $imageSelection,
                         matching: .images,
                         photoLibrary: .shared()) {
                ZStack {
                    switch imageState {
                    case .loading:
                        ProgressView()
                            .frame(width: 100, height: 100)
                    case .failure:
                        VStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.red)
                            Text("Error loading image")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .frame(width: 100, height: 100)
                    case .empty:
                        MonogramView(name: conversation.name ?? "Group")
                            .frame(width: 100, height: 100)
                    case let .success(image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 100, height: 100)
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
                    .frame(width: 100, height: 100)
                }
            }
            .buttonStyle(.borderless)
        }
    }

    private var groupNameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .font(.headline)

            VStack(spacing: 4) {
                TextField("Group name", text: $groupName)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: groupName) { _, newValue in
                        if newValue.count > nameCharacterLimit {
                            groupName = String(newValue.prefix(nameCharacterLimit))
                        }
                    }

                HStack {
                    Spacer()
                    Text("\(groupName.count)/\(nameCharacterLimit)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var groupDescriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description")
                .font(.headline)

            VStack(spacing: 4) {
                TextField(
                    "Working towards the Bedrock milestone: world-class messaging on tomorrow's foundations " +
                    "(well underway)",
                    text: $groupDescription,
                    axis: .vertical
                )
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
                    .onChange(of: groupDescription) { _, newValue in
                        if newValue.count > descriptionCharacterLimit {
                            groupDescription = String(newValue.prefix(descriptionCharacterLimit))
                        }
                    }

                HStack {
                    Spacer()
                    Text("\(groupDescription.count)/\(descriptionCharacterLimit)")
                        .font(.caption)
                        .foregroundColor(.secondary)
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

    private var adminApprovalSection: some View {
        VStack(spacing: 16) {
            Toggle("Require Admin Approval", isOn: $requireAdminApproval)
                .font(.body)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private func saveGroupChanges() async {
        isSaving = true

        do {
            var hasChanges = false

            // Check if name changed
            if groupName != conversation.name {
                hasChanges = true
                try await updateGroupName()
            }

            // Check if description changed
            if groupDescription != conversation.description {
                hasChanges = true
                try await updateGroupDescription()
            }

            // Check if image changed
            if let uploadedImageURL = uploadedImageURL {
                hasChanges = true
                try await updateGroupImage(imageURL: uploadedImageURL)
            }

            if hasChanges {
                // Show success message
                await MainActor.run {
                    alertMessage = "Group updated successfully"
                    showingAlert = true
                }

                // Dismiss after a short delay
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                await MainActor.run {
                    dismiss()
                }
            } else {
                // No changes, just dismiss
                await MainActor.run {
                    dismiss()
                }
            }
        } catch {
            await MainActor.run {
                alertMessage = "Failed to update group: \(error.localizedDescription)"
                showingAlert = true
                isSaving = false
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

        // Convert SwiftUI Image to UIImage data
        guard let uiImage = image.asUIImage(),
              let imageData = uiImage.jpegData(compressionQuality: 0.8) else {
            throw GroupImage.GroupImageError.importFailed
        }

        // Create multipart upload request to Convos API
        let baseURL = Secrets.CONVOS_API_BASE_URL
        guard let uploadURL = URL(string: "\(baseURL)v1/attachments/upload") else {
            throw GroupImage.GroupImageError.importFailed
        }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let body = Data()

//        @lourou
//        Add file data
//        guard let boundaryData = "--\(boundary)\r\n".data(using: .utf8),
//              let dispositionData = "Content-Disposition: form-data; name=\"file\";
//        filename=\"group-image.jpg\"\r\n".data(using: .utf8),
//              let contentTypeData = "Content-Type: image/jpeg\r\n\r\n".data(using: .utf8),
//              let endingData = "\r\n--\(boundary)--\r\n".data(using: .utf8) else {
//            throw GroupImage.GroupImageError.importFailed
//        }
//        
//        body.append(boundaryData)
//        body.append(dispositionData)
//        body.append(contentTypeData)
//        body.append(imageData)
//        body.append(endingData)

        request.httpBody = body

        // Perform upload
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GroupImage.GroupImageError.importFailed
        }

        // Parse response to get uploaded URL
        struct UploadResponse: Codable {
            let url: String
        }

        let uploadResponse = try JSONDecoder().decode(UploadResponse.self, from: data)

        Logger.info("Successfully uploaded image to: \(uploadResponse.url)")
        return uploadResponse.url
    }
}

// MARK: - Helper Extensions

extension Image {
    func asUIImage() -> UIImage? {
        let controller = UIHostingController(rootView: self)
        let view = controller.view

        let targetSize = CGSize(width: 300, height: 300)
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
