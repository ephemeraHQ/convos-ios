import Combine
import Foundation
import GRDB
import UIKit
import XMTPiOS

// MARK: - Group Metadata Writer Protocol

public protocol ConversationMetadataWriterProtocol {
    func updateGroupName(conversationId: String, name: String) async throws
    func updateGroupDescription(conversationId: String, description: String) async throws
    func updateGroupImageUrl(conversationId: String, imageURL: String) async throws
    func addGroupMembers(conversationId: String, memberInboxIds: [String]) async throws
    func removeGroupMembers(conversationId: String, memberInboxIds: [String]) async throws
    func promoteToAdmin(conversationId: String, memberInboxId: String) async throws
    func demoteFromAdmin(conversationId: String, memberInboxId: String) async throws
    func promoteToSuperAdmin(conversationId: String, memberInboxId: String) async throws
    func demoteFromSuperAdmin(conversationId: String, memberInboxId: String) async throws
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

    private func getInviteCode(for conversationId: String) async throws -> String? {
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()
        let currentUserInboxId = inboxReady.client.inboxId

        return try await databaseWriter.read { db in
            try DBInvite
                .filter(DBInvite.Columns.conversationId == conversationId)
                .filter(DBInvite.Columns.creatorInboxId == currentUserInboxId)
                .fetchOne(db)?
                .id
        }
    }

    // MARK: - Group Metadata Updates

    func updateGroupName(conversationId: String, name: String) async throws {
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()

        let truncatedName = name.count > NameLimits.maxConversationNameLength ? String(name.prefix(NameLimits.maxConversationNameLength)) : name

        guard let conversation = try await inboxReady.client.conversation(with: conversationId),
              case .group(let group) = conversation else {
            throw GroupMetadataError.groupNotFound(conversationId: conversationId)
        }

        // Update backend invite metadata if invite exists
        if let inviteCode = try await getInviteCode(for: conversationId) {
            Logger.info("Found invite code for conversation \(conversationId): \(inviteCode)")
            do {
                try await inboxReady.apiClient.updateInviteName(inviteCode, name: truncatedName)
                Logger.info("Updated backend invite name for conversation \(conversationId)")
            } catch {
                // Continue with XMTP update even if backend update fails
            }
        }

        try await group.updateName(name: truncatedName)

        try await databaseWriter.write { db in
            if let localConversation = try DBConversation
                .filter(DBConversation.Columns.id == conversationId)
                .fetchOne(db) {
                let updatedConversation = localConversation.with(name: truncatedName)
                try updatedConversation.save(db)
                Logger.info("Updated local conversation name for \(conversationId): \(truncatedName)")
            }
        }

        Logger.info("Updated conversation name for \(conversationId): \(truncatedName)")
    }

    func updateGroupDescription(conversationId: String, description: String) async throws {
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()

        guard let conversation = try await inboxReady.client.conversation(with: conversationId),
              case .group(let group) = conversation else {
            throw GroupMetadataError.groupNotFound(conversationId: conversationId)
        }

        // Update backend invite metadata if invite exists
        if let inviteCode = try await getInviteCode(for: conversationId) {
            Logger.info("Found invite code for conversation \(conversationId): \(inviteCode)")
            do {
                try await inboxReady.apiClient.updateInviteDescription(inviteCode, description: description)
            } catch {
                // Continue with XMTP update even if backend update fails
            }
        }

        try await group.updateDescription(description: description)

        try await databaseWriter.write { db in
            if let localConversation = try DBConversation
                .filter(DBConversation.Columns.id == conversationId)
                .fetchOne(db) {
                let updatedConversation = localConversation.with(description: description)
                try updatedConversation.save(db)
                Logger.info("Updated local conversation description for \(conversationId): \(description)")
            }
        }

        Logger.info("Updated conversation description for \(conversationId): \(description)")
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
                try await self.updateGroupImageUrl(conversationId: conversation.id, imageURL: uploadedURL)
                ImageCache.shared.setImage(resizedImage, for: conversation)
            } catch {
                Logger.error("Failed updating group image URL: \(error.localizedDescription)")
            }
        }
    }

    func updateGroupImageUrl(conversationId: String, imageURL: String) async throws {
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()

        guard let conversation = try await inboxReady.client.conversation(with: conversationId),
              case .group(let group) = conversation else {
            throw GroupMetadataError.groupNotFound(conversationId: conversationId)
        }

        // Update backend invite metadata if invite exists
        if let inviteCode = try await getInviteCode(for: conversationId) {
            Logger.info("Found invite code for conversation \(conversationId): \(inviteCode)")
            do {
                try await inboxReady.apiClient.updateInviteImageUrl(inviteCode, imageUrl: imageURL)
            } catch {
                // Continue with XMTP update even if backend update fails
            }
        }

        try await group.updateImageUrl(imageUrl: imageURL)

        try await databaseWriter.write { db in
            if let localConversation = try DBConversation
                .filter(DBConversation.Columns.id == conversationId)
                .fetchOne(db) {
                let updatedConversation = localConversation.with(imageURLString: imageURL)
                try updatedConversation.save(db)
                Logger.info("Updated local conversation image for \(conversationId): \(imageURL)")
            }
        }

        Logger.info("Updated conversation image for \(conversationId): \(imageURL)")
    }

    // MARK: - Member Management

    func addGroupMembers(conversationId: String, memberInboxIds: [String]) async throws {
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()

        guard let conversation = try await inboxReady.client.conversation(with: conversationId),
              case .group(let group) = conversation else {
            throw GroupMetadataError.groupNotFound(conversationId: conversationId)
        }

        _ = try await group.addMembers(inboxIds: memberInboxIds)

        try await databaseWriter.write { db in
            for memberInboxId in memberInboxIds {
                let conversationMember = DBConversationMember(
                    conversationId: conversationId,
                    inboxId: memberInboxId,
                    role: .member,
                    consent: .allowed,
                    createdAt: Date()
                )
                try conversationMember.save(db)
                Logger.info("Added local group member \(memberInboxId) to \(conversationId)")
            }
        }

        Logger.info("Added members to group \(conversationId): \(memberInboxIds)")
    }

    func removeGroupMembers(conversationId: String, memberInboxIds: [String]) async throws {
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()

        guard let conversation = try await inboxReady.client.conversation(with: conversationId),
              case .group(let group) = conversation else {
            throw GroupMetadataError.groupNotFound(conversationId: conversationId)
        }

        try await group.removeMembers(inboxIds: memberInboxIds)

        try await databaseWriter.write { db in
            for memberInboxId in memberInboxIds {
                try DBConversationMember
                    .filter(DBConversationMember.Columns.conversationId == conversationId)
                    .filter(DBConversationMember.Columns.inboxId == memberInboxId)
                    .deleteAll(db)
                Logger.info("Removed local group member \(memberInboxId) from \(conversationId)")
            }
        }

        Logger.info("Removed members from group \(conversationId): \(memberInboxIds)")
    }

    // MARK: - Admin Management

    func promoteToAdmin(conversationId: String, memberInboxId: String) async throws {
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()

        guard let conversation = try await inboxReady.client.conversation(with: conversationId),
              case .group(let group) = conversation else {
            throw GroupMetadataError.groupNotFound(conversationId: conversationId)
        }

        try await group.addAdmin(inboxId: memberInboxId)

        try await databaseWriter.write { db in
            if let member = try DBConversationMember
                .filter(DBConversationMember.Columns.conversationId == conversationId)
                .filter(DBConversationMember.Columns.inboxId == memberInboxId)
                .fetchOne(db) {
                let updatedMember = member.with(role: .admin)
                try updatedMember.save(db)
                Logger.info("Updated local member \(memberInboxId) role to admin in \(conversationId)")
            }
        }

        Logger.info("Promoted \(memberInboxId) to admin in group \(conversationId)")
    }

    func demoteFromAdmin(conversationId: String, memberInboxId: String) async throws {
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()

        guard let conversation = try await inboxReady.client.conversation(with: conversationId),
              case .group(let group) = conversation else {
            throw GroupMetadataError.groupNotFound(conversationId: conversationId)
        }

        try await group.removeAdmin(inboxId: memberInboxId)
        try await databaseWriter.write { db in
            if let member = try DBConversationMember
                .filter(DBConversationMember.Columns.conversationId == conversationId)
                .filter(DBConversationMember.Columns.inboxId == memberInboxId)
                .fetchOne(db) {
                let updatedMember = member.with(role: .member)
                try updatedMember.save(db)
                Logger.info("Updated local member \(memberInboxId) role to member in \(conversationId)")
            }
        }

        Logger.info("Demoted \(memberInboxId) from admin in group \(conversationId)")
    }

    func promoteToSuperAdmin(conversationId: String, memberInboxId: String) async throws {
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()

        guard let conversation = try await inboxReady.client.conversation(with: conversationId),
              case .group(let group) = conversation else {
            throw GroupMetadataError.groupNotFound(conversationId: conversationId)
        }

        try await group.addSuperAdmin(inboxId: memberInboxId)
        try await databaseWriter.write { db in
            if let member = try DBConversationMember
                .filter(DBConversationMember.Columns.conversationId == conversationId)
                .filter(DBConversationMember.Columns.inboxId == memberInboxId)
                .fetchOne(db) {
                let updatedMember = member.with(role: .superAdmin)
                try updatedMember.save(db)
                Logger.info("Updated local member \(memberInboxId) role to superAdmin in \(conversationId)")
            }
        }

        Logger.info("Promoted \(memberInboxId) to super admin in group \(conversationId)")
    }

    func demoteFromSuperAdmin(conversationId: String, memberInboxId: String) async throws {
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()

        guard let conversation = try await inboxReady.client.conversation(with: conversationId),
              case .group(let group) = conversation else {
            throw GroupMetadataError.groupNotFound(conversationId: conversationId)
        }

        try await group.removeSuperAdmin(inboxId: memberInboxId)
        try await databaseWriter.write { db in
            if let member = try DBConversationMember
                .filter(DBConversationMember.Columns.conversationId == conversationId)
                .filter(DBConversationMember.Columns.inboxId == memberInboxId)
                .fetchOne(db) {
                let updatedMember = member.with(role: .admin)
                try updatedMember.save(db)
                Logger.info("Updated local member \(memberInboxId) role to admin in \(conversationId)")
            }
        }

        Logger.info("Demoted \(memberInboxId) from super admin in group \(conversationId)")
    }
}

// MARK: - Group Metadata Errors

enum GroupMetadataError: LocalizedError {
    case clientNotAvailable
    case groupNotFound(conversationId: String)
    case memberNotFound(memberInboxId: String)
    case insufficientPermissions

    var errorDescription: String? {
        switch self {
        case .clientNotAvailable:
            return "XMTP client is not available"
        case .groupNotFound(let conversationId):
            return "Group not found: \(conversationId)"
        case .memberNotFound(let memberInboxId):
            return "Member not found: \(memberInboxId)"
        case .insufficientPermissions:
            return "Insufficient permissions to perform this action"
        }
    }
}
