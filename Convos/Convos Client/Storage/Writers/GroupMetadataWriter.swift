import Combine
import Foundation
import GRDB
import XMTPiOS

// MARK: - Group Metadata Writer Protocol

protocol GroupMetadataWriterProtocol {
    func updateGroupName(groupId: String, name: String) async throws
    func updateGroupDescription(groupId: String, description: String) async throws
    func updateGroupImageUrl(groupId: String, imageUrl: String) async throws
    func addGroupMembers(groupId: String, memberInboxIds: [String]) async throws
    func removeGroupMembers(groupId: String, memberInboxIds: [String]) async throws
    func promoteToAdmin(groupId: String, memberInboxId: String) async throws
    func demoteFromAdmin(groupId: String, memberInboxId: String) async throws
    func promoteToSuperAdmin(groupId: String, memberInboxId: String) async throws
    func demoteFromSuperAdmin(groupId: String, memberInboxId: String) async throws
}

// MARK: - Group Metadata Writer Implementation

final class GroupMetadataWriter: GroupMetadataWriterProtocol {
    private let databaseWriter: any DatabaseWriter
    private let clientPublisher: AnyPublisher<(any XMTPClientProvider)?, Never>

    init(databaseWriter: any DatabaseWriter,
         clientPublisher: AnyPublisher<(any XMTPClientProvider)?, Never>) {
        self.databaseWriter = databaseWriter
        self.clientPublisher = clientPublisher
    }

    // MARK: - Group Metadata Updates

    func updateGroupName(groupId: String, name: String) async throws {
        guard let client = await getCurrentClient() else {
            throw GroupMetadataError.clientNotAvailable
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
        guard let client = await getCurrentClient() else {
            throw GroupMetadataError.clientNotAvailable
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
        guard let client = await getCurrentClient() else {
            throw GroupMetadataError.clientNotAvailable
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

    // MARK: - Member Management

    func addGroupMembers(groupId: String, memberInboxIds: [String]) async throws {
        guard let client = await getCurrentClient() else {
            throw GroupMetadataError.clientNotAvailable
        }

        guard let conversation = try await client.conversation(with: groupId),
              case .group(let group) = conversation else {
            throw GroupMetadataError.groupNotFound(groupId: groupId)
        }

        try await group.addMembers(inboxIds: memberInboxIds)

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
        guard let client = await getCurrentClient() else {
            throw GroupMetadataError.clientNotAvailable
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
        guard let client = await getCurrentClient() else {
            throw GroupMetadataError.clientNotAvailable
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
                let updatedMember = DBConversationMember(
                    conversationId: member.conversationId,
                    memberId: member.memberId,
                    role: .admin,
                    consent: member.consent,
                    createdAt: member.createdAt
                )
                try updatedMember.save(db)
                Logger.info("Updated local member \(memberInboxId) role to admin in \(groupId)")
            }
        }

        Logger.info("Promoted \(memberInboxId) to admin in group \(groupId)")
    }

    func demoteFromAdmin(groupId: String, memberInboxId: String) async throws {
        guard let client = await getCurrentClient() else {
            throw GroupMetadataError.clientNotAvailable
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
                let updatedMember = DBConversationMember(
                    conversationId: member.conversationId,
                    memberId: member.memberId,
                    role: .member,
                    consent: member.consent,
                    createdAt: member.createdAt
                )
                try updatedMember.save(db)
                Logger.info("Updated local member \(memberInboxId) role to member in \(groupId)")
            }
        }

        Logger.info("Demoted \(memberInboxId) from admin in group \(groupId)")
    }

    func promoteToSuperAdmin(groupId: String, memberInboxId: String) async throws {
        guard let client = await getCurrentClient() else {
            throw GroupMetadataError.clientNotAvailable
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
                let updatedMember = DBConversationMember(
                    conversationId: member.conversationId,
                    memberId: member.memberId,
                    role: .superAdmin,
                    consent: member.consent,
                    createdAt: member.createdAt
                )
                try updatedMember.save(db)
                Logger.info("Updated local member \(memberInboxId) role to superAdmin in \(groupId)")
            }
        }

        Logger.info("Promoted \(memberInboxId) to super admin in group \(groupId)")
    }

    func demoteFromSuperAdmin(groupId: String, memberInboxId: String) async throws {
        guard let client = await getCurrentClient() else {
            throw GroupMetadataError.clientNotAvailable
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
                let updatedMember = DBConversationMember(
                    conversationId: member.conversationId,
                    memberId: member.memberId,
                    role: .admin,
                    consent: member.consent,
                    createdAt: member.createdAt
                )
                try updatedMember.save(db)
                Logger.info("Updated local member \(memberInboxId) role to admin in \(groupId)")
            }
        }

        Logger.info("Demoted \(memberInboxId) from super admin in group \(groupId)")
    }

    // MARK: - Private Helper Methods

    private func getCurrentClient() async -> (any XMTPClientProvider)? {
        return await withCheckedContinuation { continuation in
            let cancellable = clientPublisher
                .first()
                .sink { client in
                    continuation.resume(returning: client)
                }

            // Keep the cancellable alive until the continuation resumes
            _ = cancellable
        }
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
