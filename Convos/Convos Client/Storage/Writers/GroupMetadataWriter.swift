import Combine
import Foundation
import GRDB
import XMTPiOS

// MARK: - Group Metadata Writer Protocol

protocol GroupMetadataWriterProtocol {
    func updateGroupName(groupId: String, name: String) async throws
    func updateGroupDescription(groupId: String, description: String) async throws
    func updateGroupImageUrl(groupId: String, imageUrl: String) async throws
    func uploadAndUpdateGroupImage(groupId: String, imageData: Data, filename: String) async throws -> String
    func addGroupMembers(groupId: String, memberInboxIds: [String]) async throws
    func removeGroupMembers(groupId: String, memberInboxIds: [String]) async throws
    func promoteToAdmin(groupId: String, memberInboxId: String) async throws
    func demoteFromAdmin(groupId: String, memberInboxId: String) async throws
    func promoteToSuperAdmin(groupId: String, memberInboxId: String) async throws
    func demoteFromSuperAdmin(groupId: String, memberInboxId: String) async throws
}

// MARK: - Group Metadata Writer Implementation

final class GroupMetadataWriter: GroupMetadataWriterProtocol {
    private let clientValue: PublisherValue<AnyClientProvider>
    private let inboxReadyValue: PublisherValue<InboxReadyResult>
    private let databaseWriter: any DatabaseWriter

    init(client: AnyClientProvider?,
         clientPublisher: AnyClientProviderPublisher,
         inboxReadyValue: PublisherValue<InboxReadyResult>,
         databaseWriter: any DatabaseWriter) {
        self.clientValue = .init(initial: client, upstream: clientPublisher)
        self.inboxReadyValue = inboxReadyValue
        self.databaseWriter = databaseWriter
    }

    // MARK: - Group Metadata Updates

    func updateGroupName(groupId: String, name: String) async throws {
        guard let client = clientValue.value else {
            throw InboxStateError.inboxNotReady
        }

        guard let conversation = try await client.conversation(with: groupId),
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
        guard let client = clientValue.value else {
            throw InboxStateError.inboxNotReady
        }

        guard let conversation = try await client.conversation(with: groupId),
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

    func updateGroupImageUrl(groupId: String, imageUrl: String) async throws {
        guard let client = clientValue.value else {
            throw InboxStateError.inboxNotReady
        }

        guard let conversation = try await client.conversation(with: groupId),
              case .group(let group) = conversation else {
            throw GroupMetadataError.groupNotFound(groupId: groupId)
        }

        try await group.updateImageUrl(imageUrl: imageUrl)

        try await databaseWriter.write { db in
            if let localConversation = try DBConversation
                .filter(DBConversation.Columns.id == groupId)
                .fetchOne(db) {
                let updatedConversation = localConversation.with(imageURLString: imageUrl)
                try updatedConversation.save(db)
                Logger.info("Updated local group image for \(groupId): \(imageUrl)")
            }
        }

        Logger.info("Updated group image for \(groupId): \(imageUrl)")
    }

    func uploadAndUpdateGroupImage(groupId: String, imageData: Data, filename: String) async throws -> String {
        guard let inboxReady = inboxReadyValue.value else {
            throw InboxStateError.inboxNotReady
        }

        Logger.info("Starting group image upload for group \(groupId), file: \(filename)")

        // Step 1: Upload the image to get the public URL
        let uploadedURL = try await inboxReady.apiClient.uploadAttachment(
            data: imageData,
            filename: filename,
            contentType: "image/jpeg",
            acl: "public-read"
        )

        Logger.info("Group image uploaded successfully for group \(groupId), URL: \(uploadedURL)")

        // Step 2: Update the group metadata with the new image URL
        try await updateGroupImageUrl(groupId: groupId, imageUrl: uploadedURL)

        Logger.info("Group image metadata updated for group \(groupId)")

        return uploadedURL
    }

    // MARK: - Member Management

    func addGroupMembers(groupId: String, memberInboxIds: [String]) async throws {
        guard let client = clientValue.value else {
            throw InboxStateError.inboxNotReady
        }

        guard let conversation = try await client.conversation(with: groupId),
              case .group(let group) = conversation else {
            throw GroupMetadataError.groupNotFound(groupId: groupId)
        }

        _ = try await group.addMembers(inboxIds: memberInboxIds)

        try await databaseWriter.write { db in
            for memberInboxId in memberInboxIds {
                let conversationMember = DBConversationMember(
                    conversationId: groupId,
                    memberId: memberInboxId,
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
        guard let client = clientValue.value else {
            throw InboxStateError.inboxNotReady
        }

        guard let conversation = try await client.conversation(with: groupId),
              case .group(let group) = conversation else {
            throw GroupMetadataError.groupNotFound(groupId: groupId)
        }

        try await group.removeMembers(inboxIds: memberInboxIds)

        try await databaseWriter.write { db in
            for memberInboxId in memberInboxIds {
                try DBConversationMember
                    .filter(DBConversationMember.Columns.conversationId == groupId)
                    .filter(DBConversationMember.Columns.memberId == memberInboxId)
                    .deleteAll(db)
                Logger.info("Removed local group member \(memberInboxId) from \(groupId)")
            }
        }

        Logger.info("Removed members from group \(groupId): \(memberInboxIds)")
    }

    // MARK: - Admin Management

    func promoteToAdmin(groupId: String, memberInboxId: String) async throws {
        guard let client = clientValue.value else {
            throw InboxStateError.inboxNotReady
        }

        guard let conversation = try await client.conversation(with: groupId),
              case .group(let group) = conversation else {
            throw GroupMetadataError.groupNotFound(groupId: groupId)
        }

        try await group.addAdmin(inboxId: memberInboxId)

        try await databaseWriter.write { db in
            if let member = try DBConversationMember
                .filter(DBConversationMember.Columns.conversationId == groupId)
                .filter(DBConversationMember.Columns.memberId == memberInboxId)
                .fetchOne(db) {
                let updatedMember = member.with(role: .admin)
                try updatedMember.save(db)
                Logger.info("Updated local member \(memberInboxId) role to admin in \(groupId)")
            }
        }

        Logger.info("Promoted \(memberInboxId) to admin in group \(groupId)")
    }

    func demoteFromAdmin(groupId: String, memberInboxId: String) async throws {
        guard let client = clientValue.value else {
            throw InboxStateError.inboxNotReady
        }

        guard let conversation = try await client.conversation(with: groupId),
              case .group(let group) = conversation else {
            throw GroupMetadataError.groupNotFound(groupId: groupId)
        }

        try await group.removeAdmin(inboxId: memberInboxId)
        try await databaseWriter.write { db in
            if let member = try DBConversationMember
                .filter(DBConversationMember.Columns.conversationId == groupId)
                .filter(DBConversationMember.Columns.memberId == memberInboxId)
                .fetchOne(db) {
                let updatedMember = member.with(role: .member)
                try updatedMember.save(db)
                Logger.info("Updated local member \(memberInboxId) role to member in \(groupId)")
            }
        }

        Logger.info("Demoted \(memberInboxId) from admin in group \(groupId)")
    }

    func promoteToSuperAdmin(groupId: String, memberInboxId: String) async throws {
        guard let client = clientValue.value else {
            throw InboxStateError.inboxNotReady
        }

        guard let conversation = try await client.conversation(with: groupId),
              case .group(let group) = conversation else {
            throw GroupMetadataError.groupNotFound(groupId: groupId)
        }

        try await group.addSuperAdmin(inboxId: memberInboxId)
        try await databaseWriter.write { db in
            if let member = try DBConversationMember
                .filter(DBConversationMember.Columns.conversationId == groupId)
                .filter(DBConversationMember.Columns.memberId == memberInboxId)
                .fetchOne(db) {
                let updatedMember = member.with(role: .superAdmin)
                try updatedMember.save(db)
                Logger.info("Updated local member \(memberInboxId) role to superAdmin in \(groupId)")
            }
        }

        Logger.info("Promoted \(memberInboxId) to super admin in group \(groupId)")
    }

    func demoteFromSuperAdmin(groupId: String, memberInboxId: String) async throws {
        guard let client = clientValue.value else {
            throw InboxStateError.inboxNotReady
        }

        guard let conversation = try await client.conversation(with: groupId),
              case .group(let group) = conversation else {
            throw GroupMetadataError.groupNotFound(groupId: groupId)
        }

        try await group.removeSuperAdmin(inboxId: memberInboxId)
        try await databaseWriter.write { db in
            if let member = try DBConversationMember
                .filter(DBConversationMember.Columns.conversationId == groupId)
                .filter(DBConversationMember.Columns.memberId == memberInboxId)
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
