import Foundation

public struct ConversationUpdate: Hashable, Codable, Sendable {
    public struct MetadataChange: Hashable, Codable, Sendable {
        public enum Field: String, Codable, Sendable {
            case name = "group_name",
                 description = "description",
                 image = "group_image_url_square",
                 expiresAt = "expiresAt",
                 metadata = "app_data",
                 unknown

            var showsInMessagesList: Bool {
                switch self {
                case .expiresAt, .unknown, .metadata:
                    false
                default:
                    true
                }
            }
        }
        public let field: Field
        public let oldValue: String?
        public let newValue: String?
    }

    public let creator: ConversationMember
    public let addedMembers: [ConversationMember]
    public let removedMembers: [ConversationMember]
    public let metadataChanges: [MetadataChange]

    public var profile: Profile? {
        if !addedMembers.isEmpty && !removedMembers.isEmpty {
            return creator.profile
        } else if !addedMembers.isEmpty {
            if addedMembers.count == 1, let member = addedMembers.first {
                return member.profile
            } else {
                return nil
            }
        } else if let metadataChange = metadataChanges.first,
                  metadataChange.field == .name {
            return creator.profile
        } else if let metadataChange = metadataChanges.first,
                  metadataChange.field == .image,
                  metadataChange.newValue != nil {
            return creator.profile
        } else if let metadataChange = metadataChanges.first,
                  metadataChange.field == .description {
            return creator.profile
        } else if !removedMembers.isEmpty {
            return nil
        } else {
            return nil
        }
    }

    var showsInMessagesList: Bool {
        guard metadataChanges.allSatisfy({ $0.field.showsInMessagesList }) else {
            return false
        }
        return !summary.isEmpty
    }

    public var summary: String {
        let creatorDisplayName = creator.isCurrentUser ? "You" : creator.profile.displayName
        if !addedMembers.isEmpty && !removedMembers.isEmpty {
            return "\(creatorDisplayName) added and removed members from the convo"
        } else if !addedMembers.isEmpty {
            if addedMembers.count == 1, let member = addedMembers.first,
               member.isCurrentUser {
                let asString = member.profile.name != nil ? "as \(member.profile.displayName)" : "anonymously as \(member.profile.displayName)"
                return "You joined \(asString)"
            }
            return "\(addedMembers.formattedNamesString) joined by invitation"
        } else if let metadataChange = metadataChanges.first,
                  metadataChange.field == .name,
                  let updatedName = metadataChange.newValue {
            return "\(creatorDisplayName) changed the convo name to \"\(updatedName)\""
        } else if let metadataChange = metadataChanges.first,
                  metadataChange.field == .image,
                  metadataChange.newValue != nil {
            return "\(creatorDisplayName) changed the convo photo"
        } else if let metadataChange = metadataChanges.first,
                  metadataChange.field == .description,
                  let newValue = metadataChange.newValue {
            return "\(creatorDisplayName) changed the convo description to \"\(newValue)\""
        } else if !removedMembers.isEmpty {
            return ""
        } else {
            return ""
        }
    }
}
