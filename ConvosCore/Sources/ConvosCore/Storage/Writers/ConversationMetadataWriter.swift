import Combine
import Foundation
import GRDB
import UIKit
import XMTPiOS

// MARK: - Conversation Metadata Writer Protocol

public protocol ConversationMetadataWriterProtocol {
    func updateName(_ name: String, for conversationId: String) async throws
    func updateDescription(_ description: String, for conversationId: String) async throws
    func updateImageUrl(_ imageURL: String, for conversationId: String) async throws
    func addMembers(_ memberInboxIds: [String], to conversationId: String) async throws
    func removeMembers(_ memberInboxIds: [String], from conversationId: String) async throws
    func promoteToAdmin(_ memberInboxId: String, in conversationId: String) async throws
    func demoteFromAdmin(_ memberInboxId: String, in conversationId: String) async throws
    func promoteToSuperAdmin(_ memberInboxId: String, in conversationId: String) async throws
    func demoteFromSuperAdmin(_ memberInboxId: String, in conversationId: String) async throws
    func updateImage(_ image: UIImage, for conversation: Conversation) async throws
}

// MARK: - Conversation Metadata Writer Implementation

enum ConversationMetadataWriterError: Error {
    case failedImageCompression
}

final class ConversationMetadataWriter: ConversationMetadataWriterProtocol {
    private let inboxStateManager: any InboxStateManagerProtocol
    private let databaseWriter: any DatabaseWriter

    init(inboxStateManager: any InboxStateManagerProtocol,
         databaseWriter: any DatabaseWriter) {
        self.inboxStateManager = inboxStateManager
        self.databaseWriter = databaseWriter
    }

    // MARK: - Conversation Metadata Updates

    func updateName(_ name: String, for conversationId: String) async throws {
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()

        let truncatedName = name.count > NameLimits.maxConversationNameLength ? String(name.prefix(NameLimits.maxConversationNameLength)) : name

        guard let conversation = try await inboxReady.client.conversation(with: conversationId),
              case .group(let group) = conversation else {
            throw ConversationMetadataError.conversationNotFound(conversationId: conversationId)
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

    func updateDescription(_ description: String, for conversationId: String) async throws {
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()

        guard let conversation = try await inboxReady.client.conversation(with: conversationId),
              case .group(let group) = conversation else {
            throw ConversationMetadataError.conversationNotFound(conversationId: conversationId)
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

    func updateImage(_ image: UIImage, for conversation: Conversation) async throws {
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()

        let resizedImage = ImageCompression.resizeForCache(image)

        guard let compressedImageData = resizedImage.jpegData(compressionQuality: 0.8) else {
            throw ConversationMetadataWriterError.failedImageCompression
        }

        let filename = "conversation-image-\(UUID().uuidString).jpg"

        _ = try await inboxReady.apiClient.uploadAttachmentAndExecute(
            data: compressedImageData,
            filename: filename
        ) { uploadedURL in
            do {
                try await self.updateImageUrl(uploadedURL, for: conversation.id)
                ImageCache.shared.setImage(resizedImage, for: conversation)
            } catch {
                Logger.error("Failed updating conversation image URL: \(error.localizedDescription)")
            }
        }
    }

    func updateImageUrl(_ imageURL: String, for conversationId: String) async throws {
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()

        guard let conversation = try await inboxReady.client.conversation(with: conversationId),
              case .group(let group) = conversation else {
            throw ConversationMetadataError.conversationNotFound(conversationId: conversationId)
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

    func addMembers(_ memberInboxIds: [String], to conversationId: String) async throws {
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()

        guard let conversation = try await inboxReady.client.conversation(with: conversationId),
              case .group(let group) = conversation else {
            throw ConversationMetadataError.conversationNotFound(conversationId: conversationId)
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
                Logger.info("Added local conversation member \(memberInboxId) to \(conversationId)")
            }
        }

        Logger.info("Added members to conversation \(conversationId): \(memberInboxIds)")
    }

    func removeMembers(_ memberInboxIds: [String], from conversationId: String) async throws {
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()

        guard let conversation = try await inboxReady.client.conversation(with: conversationId),
              case .group(let group) = conversation else {
            throw ConversationMetadataError.conversationNotFound(conversationId: conversationId)
        }

        try await group.removeMembers(inboxIds: memberInboxIds)

        try await databaseWriter.write { db in
            for memberInboxId in memberInboxIds {
                try DBConversationMember
                    .filter(DBConversationMember.Columns.conversationId == conversationId)
                    .filter(DBConversationMember.Columns.inboxId == memberInboxId)
                    .deleteAll(db)
                Logger.info("Removed local conversation member \(memberInboxId) from \(conversationId)")
            }
        }

        Logger.info("Removed members from conversation \(conversationId): \(memberInboxIds)")
    }

    // MARK: - Admin Management

    func promoteToAdmin(_ memberInboxId: String, in conversationId: String) async throws {
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()

        guard let conversation = try await inboxReady.client.conversation(with: conversationId),
              case .group(let group) = conversation else {
            throw ConversationMetadataError.conversationNotFound(conversationId: conversationId)
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

        Logger.info("Promoted \(memberInboxId) to admin in conversation \(conversationId)")
    }

    func demoteFromAdmin(_ memberInboxId: String, in conversationId: String) async throws {
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()

        guard let conversation = try await inboxReady.client.conversation(with: conversationId),
              case .group(let group) = conversation else {
            throw ConversationMetadataError.conversationNotFound(conversationId: conversationId)
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

        Logger.info("Demoted \(memberInboxId) from admin in conversation \(conversationId)")
    }

    func promoteToSuperAdmin(_ memberInboxId: String, in conversationId: String) async throws {
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()

        guard let conversation = try await inboxReady.client.conversation(with: conversationId),
              case .group(let group) = conversation else {
            throw ConversationMetadataError.conversationNotFound(conversationId: conversationId)
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

        Logger.info("Promoted \(memberInboxId) to super admin in conversation \(conversationId)")
    }

    func demoteFromSuperAdmin(_ memberInboxId: String, in conversationId: String) async throws {
        let inboxReady = try await inboxStateManager.waitForInboxReadyResult()

        guard let conversation = try await inboxReady.client.conversation(with: conversationId),
              case .group(let group) = conversation else {
            throw ConversationMetadataError.conversationNotFound(conversationId: conversationId)
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

        Logger.info("Demoted \(memberInboxId) from super admin in conversation \(conversationId)")
    }
}

// MARK: - Conversation Metadata Errors

enum ConversationMetadataError: LocalizedError {
    case clientNotAvailable
    case conversationNotFound(conversationId: String)
    case memberNotFound(memberInboxId: String)
    case insufficientPermissions

    var errorDescription: String? {
        switch self {
        case .clientNotAvailable:
            return "XMTP client is not available"
        case .conversationNotFound(let conversationId):
            return "Conversation not found: \(conversationId)"
        case .memberNotFound(let memberInboxId):
            return "Member not found: \(memberInboxId)"
        case .insufficientPermissions:
            return "Insufficient permissions to perform this action"
        }
    }
}
