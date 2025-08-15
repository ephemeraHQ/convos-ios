import Foundation
import GRDB
import UIKit

protocol MyProfileWriterProtocol {
    func update(displayName: String) async throws
    func update(avatar: UIImage?) async throws
}

enum MyProfileWriterError: Error {
    case imageCompressionFailed
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

    deinit {
        cleanup()
    }

    func cleanup() {
        inboxReadyValue.dispose()
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
            if let foundProfile = try MemberProfile.fetchOne(db, key: inboxId) {
                Logger.info("Found profile: \(foundProfile)")
                return foundProfile
            } else {
                let profile = MemberProfile(inboxId: inboxId, name: nil, avatar: nil)
                try profile.save(db)
                return profile
            }
        }

        guard let avatarImage = avatar else {
            // remove avatar image URL
//            ImageCache.shared.removeImage(for: profile.hydrateProfile())
            _ = try await inboxReady.apiClient.updateProfile(inboxId: inboxId, with: profile.asUpdateRequest())
            return
        }

//        ImageCache.shared.setImage(avatarImage, for: profile.hydrateProfile())

//        let resizedImage = ImageCompression.resizeForCache(avatarImage)

        guard let compressedImageData = avatarImage.jpegData(compressionQuality: 0.8) else {
            throw MyProfileWriterError.imageCompressionFailed
        }

        let uploadedURL = try await inboxReady.apiClient.uploadAttachment(
            data: compressedImageData,
            filename: "profile-\(UUID().uuidString).jpg",
            contentType: "image/jpeg",
            acl: "public-read"
        )
        let updatedProfile = profile.with(avatar: uploadedURL)
        _ = try await inboxReady.apiClient.updateProfile(inboxId: inboxId, with: updatedProfile.asUpdateRequest())

//        ImageCache.shared.setImage(resizedImage, for: uploadedURL)

        try await databaseWriter.write { db in
            Logger.info("Updated avatar for profile: \(updatedProfile)")
            try updatedProfile.save(db)
        }
    }
}
