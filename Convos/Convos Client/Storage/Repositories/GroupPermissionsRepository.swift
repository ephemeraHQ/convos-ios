import Combine
import Foundation
import GRDB
import XMTPiOS

// MARK: - Group Permissions Repository Protocol

protocol GroupPermissionsRepositoryProtocol {
    func getGroupPermissions(for groupId: String) async throws -> GroupPermissionPolicySet
    func getMemberRole(memberInboxId: String, in groupId: String) async throws -> MemberRole
    func canPerformAction(memberInboxId: String, action: GroupPermissionAction, in groupId: String) async throws -> Bool
    func getGroupMembers(for groupId: String) async throws -> [GroupMemberInfo]
    func addAdmin(memberInboxId: String, to groupId: String) async throws
    func removeAdmin(memberInboxId: String, from groupId: String) async throws
    func addSuperAdmin(memberInboxId: String, to groupId: String) async throws
    func removeSuperAdmin(memberInboxId: String, from groupId: String) async throws
    func addMembers(inboxIds: [String], to groupId: String) async throws
    func removeMembers(inboxIds: [String], from groupId: String) async throws
}

// MARK: - Group Permission Types

enum GroupPermissionAction: String, CaseIterable {
    case addMember = "add_member_policy"
    case removeMember = "remove_member_policy"
    case addAdmin = "add_admin_policy"
    case removeAdmin = "remove_admin_policy"
    case updateGroupName = "update_group_name_policy"
    case updateGroupDescription = "update_group_description_policy"
    case updateGroupImage = "update_group_image_url_policy"
    case updateMessageDisappearing = "update_group_pinned_frame_url_policy"
}

enum GroupPermissionLevel: String {
    case allow
    case deny
    case admin
    case superAdmin = "super_admin"
    case unknown
}

struct GroupPermissionPolicySet {
    let addMemberPolicy: GroupPermissionLevel
    let removeMemberPolicy: GroupPermissionLevel
    let addAdminPolicy: GroupPermissionLevel
    let removeAdminPolicy: GroupPermissionLevel
    let updateGroupNamePolicy: GroupPermissionLevel
    let updateGroupDescriptionPolicy: GroupPermissionLevel
    let updateGroupImagePolicy: GroupPermissionLevel
    let updateMessageDisappearingPolicy: GroupPermissionLevel

    static let defaultPolicy: GroupPermissionPolicySet = GroupPermissionPolicySet(
        addMemberPolicy: .admin,
        removeMemberPolicy: .admin,
        addAdminPolicy: .superAdmin,
        removeAdminPolicy: .superAdmin,
        updateGroupNamePolicy: .admin,
        updateGroupDescriptionPolicy: .admin,
        updateGroupImagePolicy: .admin,
        updateMessageDisappearingPolicy: .admin
    )

    static let restrictivePolicy: GroupPermissionPolicySet = GroupPermissionPolicySet(
        addMemberPolicy: .superAdmin,
        removeMemberPolicy: .superAdmin,
        addAdminPolicy: .superAdmin,
        removeAdminPolicy: .superAdmin,
        updateGroupNamePolicy: .superAdmin,
        updateGroupDescriptionPolicy: .superAdmin,
        updateGroupImagePolicy: .superAdmin,
        updateMessageDisappearingPolicy: .superAdmin
    )

    static let superAdminPolicy: GroupPermissionPolicySet = GroupPermissionPolicySet(
        addMemberPolicy: .admin,
        removeMemberPolicy: .admin,
        addAdminPolicy: .superAdmin,
        removeAdminPolicy: .superAdmin,
        updateGroupNamePolicy: .admin,
        updateGroupDescriptionPolicy: .admin,
        updateGroupImagePolicy: .admin,
        updateMessageDisappearingPolicy: .admin
    )

    static let adminPolicy: GroupPermissionPolicySet = GroupPermissionPolicySet(
        addMemberPolicy: .admin,
        removeMemberPolicy: .admin,
        addAdminPolicy: .superAdmin,
        removeAdminPolicy: .deny,
        updateGroupNamePolicy: .admin,
        updateGroupDescriptionPolicy: .admin,
        updateGroupImagePolicy: .admin,
        updateMessageDisappearingPolicy: .admin
    )

    static let memberPolicy: GroupPermissionPolicySet = GroupPermissionPolicySet(
        addMemberPolicy: .admin,
        removeMemberPolicy: .admin,
        addAdminPolicy: .deny,
        removeAdminPolicy: .deny,
        updateGroupNamePolicy: .admin,
        updateGroupDescriptionPolicy: .admin,
        updateGroupImagePolicy: .admin,
        updateMessageDisappearingPolicy: .admin
    )
}

struct GroupMemberInfo {
    let inboxId: String
    let role: MemberRole
    let consent: Consent
    let addedAt: Date
}

// MARK: - Group Permissions Repository Implementation

final class GroupPermissionsRepository: GroupPermissionsRepositoryProtocol {
    private let clientValue: PublisherValue<AnyClientProvider>
    private let databaseReader: any DatabaseReader

    init(client: AnyClientProvider?,
         clientPublisher: AnyClientProviderPublisher,
        databaseReader: any DatabaseReader) {
        self.clientValue = .init(initial: client, upstream: clientPublisher)
        self.databaseReader = databaseReader
    }

    // MARK: - Public Methods

    func getGroupPermissions(for groupId: String) async throws -> GroupPermissionPolicySet {
        guard let client = clientValue.value else {
            throw InboxStateError.inboxNotReady
        }

        guard let conversation = try await client.conversation(with: groupId),
              case .group(let group) = conversation else {
            throw GroupPermissionsError.groupNotFound(groupId: groupId)
        }

        let isCurrentUserAdmin = try group.isAdmin(inboxId: client.inboxId)
        let isCurrentUserSuperAdmin = try group.isSuperAdmin(inboxId: client.inboxId)

        // Get all group members to analyze the permission structure
        let members = try await conversation.members()
        let hasMultipleAdmins = members.filter { member in
            (try? group.isAdmin(inboxId: member.inboxId)) == true ||
            (try? group.isSuperAdmin(inboxId: member.inboxId)) == true
        }.count > 1

        // Determine permission policy based on group structure and user role
        if isCurrentUserSuperAdmin {
            // Super admins get full control but still follow hierarchical model
            return GroupPermissionPolicySet.superAdminPolicy
        } else if isCurrentUserAdmin {
            // Regular admins get standard admin permissions
            return GroupPermissionPolicySet.adminPolicy
        } else if hasMultipleAdmins {
            // Group with multiple admins - more restrictive for members
            return GroupPermissionPolicySet.memberPolicy
        } else {
            // Single admin group or member-only view - use default
            return GroupPermissionPolicySet.defaultPolicy
        }
    }

    func getMemberRole(memberInboxId: String, in groupId: String) async throws -> MemberRole {
        guard let client = clientValue.value else {
            throw InboxStateError.inboxNotReady
        }

        guard let conversation = try await client.conversation(with: groupId),
              case .group(let group) = conversation else {
            throw GroupPermissionsError.groupNotFound(groupId: groupId)
        }

        // Use XMTP SDK methods to check member roles
        if try group.isSuperAdmin(inboxId: memberInboxId) {
            return .superAdmin
        } else if try group.isAdmin(inboxId: memberInboxId) {
            return .admin
        } else {
            // Check if member exists in the group
            let members = try await conversation.members()
            let memberExists = members.contains { $0.inboxId == memberInboxId }
            if memberExists {
                return .member
            } else {
                throw GroupPermissionsError.memberNotFound(memberInboxId: memberInboxId)
            }
        }
    }

    func canPerformAction(
        memberInboxId: String,
        action: GroupPermissionAction,
        in groupId: String
    ) async throws -> Bool {
        // Get member role
        let memberRole = try await getMemberRole(memberInboxId: memberInboxId, in: groupId)

        // Get group permissions
        let permissions = try await getGroupPermissions(for: groupId)

        // Determine the required permission level for this action
        let requiredPermission: GroupPermissionLevel
        switch action {
        case .addMember:
            requiredPermission = permissions.addMemberPolicy
        case .removeMember:
            requiredPermission = permissions.removeMemberPolicy
        case .addAdmin:
            requiredPermission = permissions.addAdminPolicy
        case .removeAdmin:
            requiredPermission = permissions.removeAdminPolicy
        case .updateGroupName:
            requiredPermission = permissions.updateGroupNamePolicy
        case .updateGroupDescription:
            requiredPermission = permissions.updateGroupDescriptionPolicy
        case .updateGroupImage:
            requiredPermission = permissions.updateGroupImagePolicy
        case .updateMessageDisappearing:
            requiredPermission = permissions.updateMessageDisappearingPolicy
        }

        // Check if member meets the required permission level
        return checkPermission(memberRole: memberRole, requiredLevel: requiredPermission)
    }

    func getGroupMembers(for groupId: String) async throws -> [GroupMemberInfo] {
        guard let client = clientValue.value else {
            throw InboxStateError.inboxNotReady
        }

        guard let conversation = try await client.conversation(with: groupId),
              case .group(let group) = conversation else {
            throw GroupPermissionsError.groupNotFound(groupId: groupId)
        }

        // Get members from XMTP - members is a property, not a function
        let members = try await conversation.members()

        // Convert to our format
        var groupMemberInfos: [GroupMemberInfo] = []

        for member in members {
            // Determine role using XMTP SDK methods
            let memberRole: MemberRole
            if try group.isSuperAdmin(inboxId: member.inboxId) {
                memberRole = .superAdmin
            } else if try group.isAdmin(inboxId: member.inboxId) {
                memberRole = .admin
            } else {
                memberRole = .member
            }

            // Convert XMTP ConsentState to app's Consent type
            let consent: Consent
            switch member.consentState {
            case .allowed:
                consent = .allowed
            case .denied:
                consent = .denied
            case .unknown:
                consent = .unknown
            }

            let groupMemberInfo = GroupMemberInfo(
                inboxId: member.inboxId,
                role: memberRole,
                consent: consent,
                addedAt: Date() // XMTP doesn't provide exact add date, use current
            )

            groupMemberInfos.append(groupMemberInfo)
        }

        return groupMemberInfos
    }

    func addAdmin(memberInboxId: String, to groupId: String) async throws {
        guard let client = clientValue.value else {
            throw InboxStateError.inboxNotReady
        }

        guard let conversation = try await client.conversation(with: groupId),
              case .group(let group) = conversation else {
            throw GroupPermissionsError.groupNotFound(groupId: groupId)
        }

        try await group.addAdmin(inboxId: memberInboxId)
    }

    func removeAdmin(memberInboxId: String, from groupId: String) async throws {
        guard let client = clientValue.value else {
            throw InboxStateError.inboxNotReady
        }

        guard let conversation = try await client.conversation(with: groupId),
              case .group(let group) = conversation else {
            throw GroupPermissionsError.groupNotFound(groupId: groupId)
        }

        try await group.removeAdmin(inboxId: memberInboxId)
    }

    func addSuperAdmin(memberInboxId: String, to groupId: String) async throws {
        guard let client = clientValue.value else {
            throw InboxStateError.inboxNotReady
        }

        guard let conversation = try await client.conversation(with: groupId),
              case .group(let group) = conversation else {
            throw GroupPermissionsError.groupNotFound(groupId: groupId)
        }

        try await group.addSuperAdmin(inboxId: memberInboxId)
    }

    func removeSuperAdmin(memberInboxId: String, from groupId: String) async throws {
        guard let client = clientValue.value else {
            throw InboxStateError.inboxNotReady
        }

        guard let conversation = try await client.conversation(with: groupId),
              case .group(let group) = conversation else {
            throw GroupPermissionsError.groupNotFound(groupId: groupId)
        }

        try await group.removeSuperAdmin(inboxId: memberInboxId)
    }

    func addMembers(inboxIds: [String], to groupId: String) async throws {
        guard let client = clientValue.value else {
            throw InboxStateError.inboxNotReady
        }

        guard let conversation = try await client.conversation(with: groupId),
              case .group(let group) = conversation else {
            throw GroupPermissionsError.groupNotFound(groupId: groupId)
        }

        _ = try await group.addMembers(inboxIds: inboxIds)
    }

    func removeMembers(inboxIds: [String], from groupId: String) async throws {
        guard let client = clientValue.value else {
            throw InboxStateError.inboxNotReady
        }

        guard let conversation = try await client.conversation(with: groupId),
              case .group(let group) = conversation else {
            throw GroupPermissionsError.groupNotFound(groupId: groupId)
        }

        try await group.removeMembers(inboxIds: inboxIds)
    }

    // MARK: - Private Helper Methods

    private func checkPermission(memberRole: MemberRole, requiredLevel: GroupPermissionLevel) -> Bool {
        switch requiredLevel {
        case .allow:
            return true
        case .deny:
            return false
        case .admin:
            return memberRole == .admin || memberRole == .superAdmin
        case .superAdmin:
            return memberRole == .superAdmin
        case .unknown:
            return false
        }
    }
}

// MARK: - Group Permissions Errors

enum GroupPermissionsError: LocalizedError {
    case clientNotAvailable
    case groupNotFound(groupId: String)
    case memberNotFound(memberInboxId: String)
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .clientNotAvailable:
            return "XMTP client is not available"
        case .groupNotFound(let groupId):
            return "Group not found: \(groupId)"
        case .memberNotFound(let memberInboxId):
            return "Member not found: \(memberInboxId)"
        case .permissionDenied:
            return "Permission denied for this action"
        }
    }
}
