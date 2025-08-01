import Foundation
import GRDB

// MARK: - ConversationKind

enum ConversationKind: String, Codable, Hashable, SQLExpressible, CaseIterable {
    case group, dm
}

extension Array where Element == ConversationKind {
    static var all: [ConversationKind] {
        ConversationKind.allCases
    }

    static var groups: [ConversationKind] {
        [.group]
    }

    static var dms: [ConversationKind] {
        [.dm]
    }
}

// MARK: - Consent

enum Consent: String, Codable, Hashable, SQLExpressible, CaseIterable {
    case allowed, denied, unknown
}

extension Array where Element == Consent {
    static var all: [Consent] {
        Consent.allCases
    }

    static var allowed: [Consent] {
        [.allowed]
    }

    static var denied: [Consent] {
        [.denied]
    }

    static var securityLine: [Consent] {
        [.unknown]
    }
}

// MARK: - MemberRole

enum MemberRole: String, Codable, Hashable, CaseIterable {
    case member, admin, superAdmin = "super_admin"

    var displayName: String {
        switch self {
        case .member:
            return ""
        case .admin:
            return "Admin"
        case .superAdmin:
            return "Super Admin"
        }
    }

    var priority: Int {
        switch self {
        case .superAdmin: return 1
        case .admin: return 2
        case .member: return 3
        }
    }
}
