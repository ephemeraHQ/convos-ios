import Foundation

public struct ConversationUpdate: Hashable, Codable {
    public struct MetadataChange: Hashable, Codable {
        public enum Field: String, Codable {
            case name = "group_name",
                 description = "description",
                 image = "group_image_url_square",
                 unknown
        }
        public let field: Field
        public let oldValue: String?
        public let newValue: String?
    }

    public let creator: Profile
    public let addedMembers: [Profile]
    public let removedMembers: [Profile]
    public let metadataChanges: [MetadataChange]

    public var summary: String {
        if !addedMembers.isEmpty && !removedMembers.isEmpty {
            "\(creator.displayName) added and removed members from the convo"
        } else if !addedMembers.isEmpty {
            "\(addedMembers.formattedNamesString) joined by invitation"
        } else if !removedMembers.isEmpty {
            "\(removedMembers.formattedNamesString) left the convo"
        } else if let metadataChange = metadataChanges.first,
                  metadataChange.field == .name,
                  let updatedName = metadataChange.newValue {
            "\(creator.displayName) changed the convo name to \"\(updatedName)\""
        } else if let metadataChange = metadataChanges.first,
                  metadataChange.field == .image,
                  metadataChange.newValue != nil {
            "\(creator.displayName) changed the convo photo"
        } else if let metadataChange = metadataChanges.first,
                  metadataChange.field == .description,
                  metadataChange.newValue != nil {
            "\(creator.displayName) changed the convo description"
        } else {
            "Unknown update"
        }
    }
}
