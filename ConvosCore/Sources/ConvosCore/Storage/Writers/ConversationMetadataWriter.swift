import Combine
import Foundation
import GRDB
import UIKit
import XMTPiOS

// MARK: - Group Metadata Writer Protocol

public protocol ConversationMetadataWriterProtocol {
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

enum ConversationMetadataWriterError: Error {
    case failedImageCompression
}

final class ConversationMetadataWriter: ConversationMetadataWriterProtocol {
    private let inboxStateManager: InboxStateManager
    private let databaseWriter: any DatabaseWriter

    init(inboxStateManager: InboxStateManager,
         databaseWriter: any DatabaseWriter) {
        self.inboxStateManager = inboxStateManager
        self.databaseWriter = databaseWriter
    }

    // MARK: - Private Helpers

    private func getInviteCode(for groupId: String) async throws -> String? {
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()
        let currentUserInboxId = inboxReady.client.inboxId

        return try await databaseWriter.read { db in
            try DBInvite
                .filter(DBInvite.Columns.conversationId == groupId)
                .filter(DBInvite.Columns.creatorInboxId == currentUserInboxId)
                .fetchOne(db)?
                .id
        }
    }

    // MARK: - Group Metadata Updates

    func updateGroupName(groupId: String, name: String) async throws {
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()

        let truncatedName = name.count > NameLimits.maxConversationNameLength ? String(name.prefix(NameLimits.maxConversationNameLength)) : name

        guard let conversation = try await inboxReady.client.conversation(with: groupId),
              case .group(let group) = conversation else {
            throw GroupMetadataError.groupNotFound(groupId: groupId)
        }

        // Update backend invite metadata if invite exists
        if let inviteCode = try await getInviteCode(for: groupId) {
            Logger.info("Found invite code for group \(groupId): \(inviteCode)")
            do {
                try await inboxReady.apiClient.updateInviteName(inviteCode, name: truncatedName)
                Logger.info("Updated backend invite name for \(groupId)")
            } catch {
                // Continue with XMTP update even if backend update fails
            }
        }

        try await group.updateName(name: truncatedName)

        try await databaseWriter.write { db in
            if let localConversation = try DBConversation
                .filter(DBConversation.Columns.id == groupId)
                .fetchOne(db) {
                let updatedConversation = localConversation.with(name: truncatedName)
                try updatedConversation.save(db)
                Logger.info("Updated local group name for \(groupId): \(truncatedName)")
            }
        }

        Logger.info("Updated group name for \(groupId): \(truncatedName)")
    }

    func updateGroupDescription(groupId: String, description: String) async throws {
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()

        guard let conversation = try await inboxReady.client.conversation(with: groupId),
              case .group(let group) = conversation else {
            throw GroupMetadataError.groupNotFound(groupId: groupId)
        }

        // Update backend invite metadata if invite exists
        if let inviteCode = try await getInviteCode(for: groupId) {
            Logger.info("🔍 Found invite code for group \(groupId): \(inviteCode)")
            do {
                Logger.info("🚀 Starting backend invite description update...")
                try await inboxReady.apiClient.updateInviteDescription(inviteCode, description: description)
                Logger.info("✅ Backend invite description updated successfully for \(groupId)")
            } catch {
                Logger.error("❌ Failed to update backend invite description: \(error)")
                Logger.error("🔍 Full error: \(String(describing: error))")
                // Continue with XMTP update even if backend update fails
            }
        } else {
            Logger.info("ℹ️ No invite code found for group \(groupId), skipping backend update")
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
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()

        let resizedImage = ImageCompression.resizeForCache(image)

        guard let compressedImageData = resizedImage.jpegData(compressionQuality: 0.8) else {
            throw ConversationMetadataWriterError.failedImageCompression
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
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()

        guard let conversation = try await inboxReady.client.conversation(with: groupId),
              case .group(let group) = conversation else {
            throw GroupMetadataError.groupNotFound(groupId: groupId)
        }

        // Update backend invite metadata if invite exists
        if let inviteCode = try await getInviteCode(for: groupId) {
            Logger.info("🔍 Found invite code for group \(groupId): \(inviteCode)")
            do {
                Logger.info("🚀 Starting backend invite image URL update...")
                try await inboxReady.apiClient.updateInviteImageUrl(inviteCode, imageUrl: imageURL)
                Logger.info("✅ Backend invite image URL updated successfully for \(groupId)")
            } catch {
                Logger.error("❌ Failed to update backend invite image URL: \(error)")
                Logger.error("🔍 Full error: \(String(describing: error))")
                // Continue with XMTP update even if backend update fails
            }
        } else {
            Logger.info("ℹ️ No invite code found for group \(groupId), skipping backend update")
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
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()

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
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()

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
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()

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
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()

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
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()

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
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()

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
