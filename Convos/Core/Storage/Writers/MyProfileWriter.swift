import Foundation
import GRDB
import UIKit

protocol MyProfileWriterProtocol {
    func update(displayName: String) async throws
    func update(avatar: UIImage?) async throws
}

class MyProfileWriter: MyProfileWriterProtocol {
    private let inboxReadyValue: PublisherValue<InboxReadyResult>
    private let databaseWriter: any DatabaseWriter

    init(
        inboxReadyValue: PublisherValue<InboxReadyResult>,
        databaseWriter: any DatabaseWriter
    ) {
        self.inboxReadyValue = inboxReadyValue
        self.databaseWriter = databaseWriter
    }

    func update(displayName: String) async throws {
        guard let inboxReady = inboxReadyValue.value else {
            return
        }

        let displayName: String? = displayName.isEmpty ? nil : displayName
        let inboxId = inboxReady.client.inboxId
        let profile = try await databaseWriter.write { db in
            let member = Member(inboxId: inboxId)
            try member.save(db)
            let profile = (try MemberProfile.fetchOne(db, key: inboxId) ?? .init(
                inboxId: inboxId,
                name: displayName,
                avatar: nil
            )).with(name: displayName)
            try profile.save(db)
            return profile
        }

        _ = try await inboxReady.apiClient.updateProfile(inboxId: inboxId, with: profile.asUpdateRequest())
    }

    func update(avatar: UIImage?) async throws {
        guard let inboxReady = inboxReadyValue.value else {
            throw InboxStateError.inboxNotReady
        }

        let inboxId = inboxReady.client.inboxId
        let profile = try await databaseWriter.write { db in
            let member = Member(inboxId: inboxId)
            try member.save(db)
            var profile = try MemberProfile.fetchOne(db, key: inboxId) ?? .init(inboxId: inboxId, name: nil, avatar: nil)
            if avatar == nil {
                profile = profile.with(avatar: nil)
            }
            try profile.save(db)
            return profile
        }

        guard let avatarImage = avatar else {
            // remove avatar image URL
            ImageCache.shared.removeImage(for: profile.hydrateProfile())
            _ = try await inboxReady.apiClient.updateProfile(inboxId: inboxId, with: profile.asUpdateRequest())
            return
        }

        ImageCache.shared.setImage(avatarImage, for: profile.hydrateProfile())

        let resizedImage = ImageCompression.resizeForCache(avatarImage)

        guard let compressedImageData = resizedImage.jpegData(compressionQuality: 0.8) else {
            throw ImagePickerImageError.importFailed
        }

        let uploadedURL = try await inboxReady.apiClient.uploadAttachment(
            data: compressedImageData,
            filename: "profile-\(UUID().uuidString).jpg",
            contentType: "image/jpeg",
            acl: "public-read"
        )

        try await databaseWriter.write { db in
            try profile.with(avatar: uploadedURL).save(db)
        }
    }
}
