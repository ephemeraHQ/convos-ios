import Foundation
import UIKit

protocol GroupEditRepositoryProtocol {
    func updateGroupName(groupId: String, name: String) async throws
    func updateGroupDescription(groupId: String, description: String) async throws
    func updateGroupImage(groupId: String, imageUrl: String) async throws
    func uploadImageAndUpdateGroup(groupId: String, data: Data, filename: String, image: UIImage) async throws
}

final class GroupEditRepository: GroupEditRepositoryProtocol {
    private let messagingService: any MessagingServiceProtocol

    init(messagingService: any MessagingServiceProtocol) {
        self.messagingService = messagingService
    }

    func updateGroupName(groupId: String, name: String) async throws {
        let metadataWriter = messagingService.groupMetadataWriter()
        try await metadataWriter.updateGroupName(groupId: groupId, name: name)
    }

    func updateGroupDescription(groupId: String, description: String) async throws {
        let metadataWriter = messagingService.groupMetadataWriter()
        try await metadataWriter.updateGroupDescription(groupId: groupId, description: description)
    }

    func updateGroupImage(groupId: String, imageUrl: String) async throws {
        let metadataWriter = messagingService.groupMetadataWriter()
        try await metadataWriter.updateGroupImageUrl(groupId: groupId, imageUrl: imageUrl)
    }

    func uploadImageAndUpdateGroup(groupId: String, data: Data, filename: String, image: UIImage) async throws {
        _ = try await messagingService.uploadImageAndExecute(data: data, filename: filename) { uploadedURL in
            try await self.updateGroupImage(groupId: groupId, imageUrl: uploadedURL)
            ImageCache.shared.setImageForConversation(image, conversationId: groupId)
        }
    }
}
