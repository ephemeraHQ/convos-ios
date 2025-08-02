import Foundation

struct ConversationUpdate: Hashable, Codable {
    struct MetadataChange: Hashable, Codable {
        enum Field: String, Codable {
            case name = "group_name", image = "group_image_url_square", unknown
        }
        let field: Field
        let oldValue: String?
        let newValue: String?
    }

    let creator: Profile
    let addedMembers: [Profile]
    let removedMembers: [Profile]
    let metadataChanges: [MetadataChange]

    var summary: String {
        if !addedMembers.isEmpty && !removedMembers.isEmpty {
            "\(creator.displayName) added and removed members from the convo"
        } else if !addedMembers.isEmpty {
            "\(addedMembers.formattedNamesString) joined the convo"
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
        } else {
            "Unknown update"
        }
    }
}
