import PhotosUI
import SwiftUI

@Observable
class GroupEditState {
    private let conversation: Conversation
    private let groupMetadataWriter: any GroupMetadataWriterProtocol

    // Form state
    private var _groupName: String
    var groupName: String {
        get { _groupName }
        set { _groupName = validateGroupName(newValue) }
    }

    private var _groupDescription: String
    var groupDescription: String {
        get { _groupDescription }
        set { _groupDescription = validateGroupDescription(newValue) }
    }

    var imageState: PhotosPickerImage.State = .empty
    var currentConversationImage: UIImage?

    // UI state
    private var imageLoadingTask: Task<Void, Never>?
    var imageSelection: PhotosPickerItem? {
        didSet {
            if let imageSelection {
                imageLoadingTask?.cancel()
                imageLoadingTask = Task {
                    await loadSelectedImage(imageSelection)
                }
            }
        }
    }

    var showingAlert: Bool = false
    var alertMessage: String = ""

    // Track changes for reverting
    private var originalCachedImage: UIImage?
    private var changesSaved: Bool = false

    // Constants
    let nameCharacterLimit: Int = 100
    let descriptionCharacterLimit: Int = 300

    var canEditGroup: Bool {
        // For now, allow editing for demo purposes
        // @lourou: Use real permissions check from messaging service
        return true
    }

    var hasChanges: Bool {
        let hasImageChange = if case .success = imageState { true } else { false }
        return groupName != conversation.name ||
               groupDescription != conversation.description ||
               hasImageChange
    }

    init(conversation: Conversation, groupMetadataWriter: any GroupMetadataWriterProtocol) {
        self.conversation = conversation
        self.groupMetadataWriter = groupMetadataWriter
        self._groupName = conversation.name ?? ""
        self._groupDescription = conversation.description ?? ""
    }

    @MainActor
    func onAppear() {
        loadCurrentConversationImage()
        originalCachedImage = ImageCache.shared.image(for: conversation)
    }

    @MainActor
    func onDisappear() {
        if !changesSaved {
            revertImageChanges()
        }
    }

    @MainActor
    func onImageCacheUpdate() {
        loadCurrentConversationImage()
    }

    func validateGroupName(_ newValue: String) -> String {
        return newValue.count > nameCharacterLimit ?
            String(newValue.prefix(nameCharacterLimit)) : newValue
    }

    func validateGroupDescription(_ newValue: String) -> String {
        return newValue.count > descriptionCharacterLimit ?
            String(newValue.prefix(descriptionCharacterLimit)) : newValue
    }

    var shouldShowNameCharacterCount: Bool {
        groupName.count > nameCharacterLimit - 20
    }

    var shouldShowDescriptionCharacterCount: Bool {
        groupDescription.count > descriptionCharacterLimit - 50
    }

    func markChangesSaved() {
        changesSaved = true
    }

    func saveGroupChanges() async -> Bool {
        guard hasChanges else {
            changesSaved = true
            return true
        }

        do {
            if groupName != conversation.name {
                try await updateGroupName()
            }

            if groupDescription != conversation.description {
                try await updateGroupDescription()
            }

            if case .success = imageState {
                try await uploadImageAndUpdateProfile()
            }

            changesSaved = true
            return true
        } catch {
            Logger.error("Failed to update group: \(error)")
            await MainActor.run {
                alertMessage = "Group update failed: \(error.localizedDescription)"
                showingAlert = true
            }
            return false
        }
    }

    private func loadSelectedImage(_ imageSelection: PhotosPickerItem) async {
        let imageState = await imageSelection.loadImage()
        await MainActor.run {
            withAnimation {
                self.imageState = imageState
                if case .success(let image) = imageState {
                    ImageCache.shared.setImage(image, for: conversation)
                }
            }
        }
    }

    private func updateGroupName() async throws {
        try await groupMetadataWriter.updateGroupName(groupId: conversation.id, name: groupName)
    }

    private func updateGroupDescription() async throws {
        try await groupMetadataWriter.updateGroupDescription(groupId: conversation.id, description: groupDescription)
    }

    private func updateGroupImage(imageURL: String) async throws {
        try await groupMetadataWriter.updateGroupImageUrl(groupId: conversation.id, imageUrl: imageURL)
    }

    @MainActor
    private func loadCurrentConversationImage() {
        if let cachedImage = ImageCache.shared.image(for: conversation) {
            currentConversationImage = cachedImage
        } else {
            currentConversationImage = nil
        }
    }

    private func prepareImageForUpload() async throws -> Data {
        guard case .success(let image) = imageState else {
            throw PhotosPickerImageError.importFailed
        }

        let resizedImage = ImageCompression.resizeForCache(image)

        guard let compressedImageData = resizedImage.jpegData(compressionQuality: 0.8) else {
            throw PhotosPickerImageError.importFailed
        }

        return compressedImageData
    }

    private func uploadImageAndUpdateProfile() async throws {
        // @jarodl fix this
//        let compressedImageData = try await prepareImageForUpload()
//        let filename = "group-image-\(UUID().uuidString).jpg"
//
//        guard case .success(let uploadedImage) = imageState else {
//            throw GroupImageError.importFailed
//        }

//        _ = try await messagingService.uploadImageAndExecute(
//            data: compressedImageData,
//            filename: filename) { uploadedURL in
//            try await self.updateGroupImage(imageURL: uploadedURL)
//            ImageCache.shared.setImage(uploadedImage, for: self.conversation)
//        }
    }

    @MainActor
    private func revertImageChanges() {
        if case .success = imageState {
            if let originalImage = originalCachedImage {
                ImageCache.shared.setImage(originalImage, for: conversation)
            } else {
                ImageCache.shared.removeImage(for: conversation)
            }
        }
    }
}
