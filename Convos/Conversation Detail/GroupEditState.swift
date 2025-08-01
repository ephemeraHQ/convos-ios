import PhotosUI
import SwiftUI

@Observable
class GroupEditState {
    let conversation: Conversation

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
    var changesSaved: Bool = false

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

    init(conversation: Conversation) {
        self.conversation = conversation
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

    @MainActor
    private func loadCurrentConversationImage() {
        if let cachedImage = ImageCache.shared.image(for: conversation) {
            currentConversationImage = cachedImage
        } else {
            currentConversationImage = nil
        }
    }

    func prepareImageForUpload() async throws -> Data {
        guard case .success(let image) = imageState else {
            throw PhotosPickerImageError.importFailed
        }

        let resizedImage = ImageCompression.resizeForCache(image)

        guard let compressedImageData = resizedImage.jpegData(compressionQuality: 0.8) else {
            throw PhotosPickerImageError.importFailed
        }

        return compressedImageData
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
