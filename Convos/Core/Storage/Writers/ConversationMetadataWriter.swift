import Combine
import Foundation
import GRDB
import UIKit
import XMTPiOS

// MARK: - Group Metadata Writer Protocol

protocol ConversationMetadataWriterProtocol {
    func updateGroupName(groupId: String, name: String) async throws
    func updateGroupDescription(groupId: String, description: String) async throws
    func updateGroupImageUrl(groupId: String, imageURL: String) async throws
    func addGroupMembers(groupId: String, memberInboxIds: [String]) async throws
    func removeGroupMembers(groupId: String, memberInboxIds: [String]) async throws
    func promoteToAdmin(groupId: String, memberInboxId: String) async throws
    func demoteFromAdmin(groupId: String, memberInboxId: String) async throws
    func promoteToSuperAdmin(groupId: String, memberInboxId: String) async throws
    func demoteFromSuperAdmin(groupId: String, memberInboxId: String) async throws
    func updateGroupImage(conversation: Conversation, image: UIImage) async throws
}

// MARK: - Group Metadata Writer Implementation

final class ConversationMetadataWriter: ConversationMetadataWriterProtocol {
    private let inboxReadyValue: PublisherValue<InboxReadyResult>
    private let databaseWriter: any DatabaseWriter

    init(inboxReadyValue: PublisherValue<InboxReadyResult>,
         databaseWriter: any DatabaseWriter) {
        self.inboxReadyValue = inboxReadyValue
        self.databaseWriter = databaseWriter
    }

    // MARK: - Group Metadata Updates

    func updateGroupName(groupId: String, name: String) async throws {
        guard let inboxReady = inboxReadyValue.value else {
            throw InboxStateError.inboxNotReady
        }

        guard let conversation = try await inboxReady.client.conversation(with: groupId),
              case .group(let group) = conversation else {
            throw GroupMetadataError.groupNotFound(groupId: groupId)
        }

        try await group.updateName(name: name)

        try await databaseWriter.write { db in
            if let localConversation = try DBConversation
                .filter(DBConversation.Columns.id == groupId)
                .fetchOne(db) {
                let updatedConversation = localConversation.with(name: name)
                try updatedConversation.save(db)
                Logger.info("Updated local group name for \(groupId): \(name)")
            }
        }

        Logger.info("Updated group name for \(groupId): \(name)")
    }

    func updateGroupDescription(groupId: String, description: String) async throws {
        guard let inboxReady = inboxReadyValue.value else {
            throw InboxStateError.inboxNotReady
        }

        guard let conversation = try await inboxReady.client.conversation(with: groupId),
              case .group(let group) = conversation else {
            throw GroupMetadataError.groupNotFound(groupId: groupId)
        }

        try await group.updateDescription(description: description)

        try await databaseWriter.write { db in
            if let localConversation = try DBConversation
                .filter(DBConversation.Columns.id == groupId)
                .fetchOne(db) {
                let updatedConversation = localConversation.with(description: description)
                try updatedConversation.save(db)
                Logger.info("Updated local group description for \(groupId): \(description)")
            }
        }

        Logger.info("Updated group description for \(groupId): \(description)")
    }

    func updateGroupImage(conversation: Conversation, image: UIImage) async throws {
        guard let inboxReady = inboxReadyValue.value else {
            throw InboxStateError.inboxNotReady
        }

        let resizedImage = ImageCompression.resizeForCache(image)

        guard let compressedImageData = resizedImage.jpegData(compressionQuality: 0.8) else {
            throw ImagePickerImageError.importFailed
        }

        let filename = "group-image-\(UUID().uuidString).jpg"

        _ = try await inboxReady.apiClient.uploadAttachmentAndExecute(
            data: compressedImageData,
            filename: filename
        ) { uploadedURL in
            do {
                try await self.updateGroupImageUrl(groupId: conversation.id, imageURL: uploadedURL)
                ImageCache.shared.setImage(resizedImage, for: conversation)
            } catch {
                Logger.error("Failed updating group image URL: \(error.localizedDescription)")
            }
        }
    }

    func updateGroupImageUrl(groupId: String, imageURL: String) async throws {
        guard let inboxReady = inboxReadyValue.value else {
            throw InboxStateError.inboxNotReady
        }

        guard let conversation = try await inboxReady.client.conversation(with: groupId),
              case .group(let group) = conversation else {
            throw GroupMetadataError.groupNotFound(groupId: groupId)
        }

        try await group.updateImageUrl(imageUrl: imageURL)

        try await databaseWriter.write { db in
            if let localConversation = try DBConversation
                .filter(DBConversation.Columns.id == groupId)
                .fetchOne(db) {
                let updatedConversation = localConversation.with(imageURLString: imageURL)
                try updatedConversation.save(db)
                Logger.info("Updated local group image for \(groupId): \(imageURL)")
            }
        }

        Logger.info("Updated group image for \(groupId): \(imageURL)")
    }

    // MARK: - Member Management

    func addGroupMembers(groupId: String, memberInboxIds: [String]) async throws {
        guard let inboxReady = inboxReadyValue.value else {
            throw InboxStateError.inboxNotReady
        }

        guard let conversation = try await inboxReady.client.conversation(with: groupId),
              case .group(let group) = conversation else {
            throw GroupMetadataError.groupNotFound(groupId: groupId)
        }

        _ = try await group.addMembers(inboxIds: memberInboxIds)

        try await databaseWriter.write { db in
            for memberInboxId in memberInboxIds {
                let conversationMember = DBConversationMember(
                    conversationId: groupId,
                    inboxId: memberInboxId,
                    role: .member,
                    consent: .allowed,
                    createdAt: Date()
                )
                try conversationMember.save(db)
                Logger.info("Added local group member \(memberInboxId) to \(groupId)")
            }
        }

        Logger.info("Added members to group \(groupId): \(memberInboxIds)")
    }

    func removeGroupMembers(groupId: String, memberInboxIds: [String]) async throws {
        guard let inboxReady = inboxReadyValue.value else {
            throw InboxStateError.inboxNotReady
        }

        guard let conversation = try await inboxReady.client.conversation(with: groupId),
              case .group(let group) = conversation else {
            throw GroupMetadataError.groupNotFound(groupId: groupId)
        }

        try await group.removeMembers(inboxIds: memberInboxIds)

        try await databaseWriter.write { db in
            for memberInboxId in memberInboxIds {
                try DBConversationMember
                    .filter(DBConversationMember.Columns.conversationId == groupId)
                    .filter(DBConversationMember.Columns.inboxId == memberInboxId)
                    .deleteAll(db)
                Logger.info("Removed local group member \(memberInboxId) from \(groupId)")
            }
        }

        Logger.info("Removed members from group \(groupId): \(memberInboxIds)")
    }

    // MARK: - Admin Management

    func promoteToAdmin(groupId: String, memberInboxId: String) async throws {
        guard let inboxReady = inboxReadyValue.value else {
            throw InboxStateError.inboxNotReady
        }

        guard let conversation = try await inboxReady.client.conversation(with: groupId),
              case .group(let group) = conversation else {
            throw GroupMetadataError.groupNotFound(groupId: groupId)
        }

        try await group.addAdmin(inboxId: memberInboxId)

        try await databaseWriter.write { db in
            if let member = try DBConversationMember
                .filter(DBConversationMember.Columns.conversationId == groupId)
                .filter(DBConversationMember.Columns.inboxId == memberInboxId)
                .fetchOne(db) {
                let updatedMember = member.with(role: .admin)
                try updatedMember.save(db)
                Logger.info("Updated local member \(memberInboxId) role to admin in \(groupId)")
            }
        }

        Logger.info("Promoted \(memberInboxId) to admin in group \(groupId)")
    }

    func demoteFromAdmin(groupId: String, memberInboxId: String) async throws {
        guard let inboxReady = inboxReadyValue.value else {
            throw InboxStateError.inboxNotReady
        }

        guard let conversation = try await inboxReady.client.conversation(with: groupId),
              case .group(let group) = conversation else {
            throw GroupMetadataError.groupNotFound(groupId: groupId)
        }

        try await group.removeAdmin(inboxId: memberInboxId)
        try await databaseWriter.write { db in
            if let member = try DBConversationMember
                .filter(DBConversationMember.Columns.conversationId == groupId)
                .filter(DBConversationMember.Columns.inboxId == memberInboxId)
                .fetchOne(db) {
                let updatedMember = member.with(role: .member)
                try updatedMember.save(db)
                Logger.info("Updated local member \(memberInboxId) role to member in \(groupId)")
            }
        }

        Logger.info("Demoted \(memberInboxId) from admin in group \(groupId)")
    }

    func promoteToSuperAdmin(groupId: String, memberInboxId: String) async throws {
        guard let inboxReady = inboxReadyValue.value else {
            throw InboxStateError.inboxNotReady
        }

        guard let conversation = try await inboxReady.client.conversation(with: groupId),
              case .group(let group) = conversation else {
            throw GroupMetadataError.groupNotFound(groupId: groupId)
        }

        try await group.addSuperAdmin(inboxId: memberInboxId)
        try await databaseWriter.write { db in
            if let member = try DBConversationMember
                .filter(DBConversationMember.Columns.conversationId == groupId)
                .filter(DBConversationMember.Columns.inboxId == memberInboxId)
                .fetchOne(db) {
                let updatedMember = member.with(role: .superAdmin)
                try updatedMember.save(db)
                Logger.info("Updated local member \(memberInboxId) role to superAdmin in \(groupId)")
            }
        }

        Logger.info("Promoted \(memberInboxId) to super admin in group \(groupId)")
    }

    func demoteFromSuperAdmin(groupId: String, memberInboxId: String) async throws {
        guard let inboxReady = inboxReadyValue.value else {
            throw InboxStateError.inboxNotReady
        }

        guard let conversation = try await inboxReady.client.conversation(with: groupId),
              case .group(let group) = conversation else {
            throw GroupMetadataError.groupNotFound(groupId: groupId)
        }

        try await group.removeSuperAdmin(inboxId: memberInboxId)
        try await databaseWriter.write { db in
            if let member = try DBConversationMember
                .filter(DBConversationMember.Columns.conversationId == groupId)
                .filter(DBConversationMember.Columns.inboxId == memberInboxId)
                .fetchOne(db) {
                let updatedMember = member.with(role: .admin)
                try updatedMember.save(db)
                Logger.info("Updated local member \(memberInboxId) role to admin in \(groupId)")
            }
        }

        Logger.info("Demoted \(memberInboxId) from super admin in group \(groupId)")
    }
}

// MARK: - Group Metadata Errors

enum GroupMetadataError: LocalizedError {
    case clientNotAvailable
    case groupNotFound(groupId: String)
    case memberNotFound(memberInboxId: String)
    case insufficientPermissions

    var errorDescription: String? {
        switch self {
        case .clientNotAvailable:
            return "XMTP client is not available"
        case .groupNotFound(let groupId):
            return "Group not found: \(groupId)"
        case .memberNotFound(let memberInboxId):
            return "Member not found: \(memberInboxId)"
        case .insufficientPermissions:
            return "Insufficient permissions to perform this action"
        }
    }
}
