import PhotosUI
import SwiftUI

@Observable
class GroupEditState {
    private let conversation: Conversation
    private let repository: GroupEditRepositoryProtocol

    // Form state
    var groupName: String
    var groupDescription: String
    var uniqueLink: String
    var imageState: GroupImageState = .empty
    var currentConversationImage: UIImage?

    // UI state
    var imageSelection: PhotosPickerItem? {
        didSet {
            if let imageSelection {
                self.imageState = .loading
                Task {
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

    init(conversation: Conversation, repository: GroupEditRepositoryProtocol) {
        self.conversation = conversation
        self.repository = repository
        self.groupName = conversation.name ?? ""
        self.groupDescription = conversation.description ?? ""
        self.uniqueLink = "convosation"
    }

    @MainActor
    func onAppear() {
        loadCurrentConversationImage()
        originalCachedImage = ImageCache.shared.imageForConversation(conversation.id)
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

    func saveGroupChanges() async -> Bool {
        guard hasChanges else {
            changesSaved = true
            return true
        }

        changesSaved = true

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

            return true
        } catch {
            Logger.error("Failed to update group: \(error)")
            await MainActor.run {
                alertMessage = "Group update failed: \(error.localizedDescription)"
                showingAlert = true
                changesSaved = false
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
                    ImageCache.shared.setImageForConversation(image, conversationId: conversation.id)
                }
            }
        }
    }

    private func updateGroupName() async throws {
        try await repository.updateGroupName(groupId: conversation.id, name: groupName)
    }

    private func updateGroupDescription() async throws {
        try await repository.updateGroupDescription(groupId: conversation.id, description: groupDescription)
    }

    private func updateGroupImage(imageURL: String) async throws {
        try await repository.updateGroupImage(groupId: conversation.id, imageUrl: imageURL)
    }

    @MainActor
    private func loadCurrentConversationImage() {
        if let cachedImage = ImageCache.shared.imageForConversation(conversation.id) {
            currentConversationImage = cachedImage
        } else {
            currentConversationImage = nil
        }
    }

    private func prepareImageForUpload() async throws -> Data {
        guard case .success(let image) = imageState else {
            throw GroupImageError.importFailed
        }

        let resizedImage = ImageCompression.resizeForCache(image)

        guard let compressedImageData = resizedImage.jpegData(compressionQuality: 0.8) else {
            throw GroupImageError.importFailed
        }

        return compressedImageData
    }

    private func uploadImageAndUpdateProfile() async throws {
        let compressedImageData = try await prepareImageForUpload()
        let filename = "group-image-\(UUID().uuidString).jpg"

        guard case .success(let uploadedImage) = imageState else {
            throw GroupImageError.importFailed
        }

        try await repository.uploadImageAndUpdateGroup(
            groupId: conversation.id,
            data: compressedImageData,
            filename: filename,
            image: uploadedImage
        )
    }

    @MainActor
    private func revertImageChanges() {
        if case .success = imageState {
            if let originalImage = originalCachedImage {
                ImageCache.shared.setImageForConversation(originalImage, conversationId: conversation.id)
            } else {
                ImageCache.shared.removeImageForConversation(conversation.id)
            }
        }
    }
}
