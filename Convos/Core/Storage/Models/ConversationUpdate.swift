import Foundation

struct ConversationUpdate: Hashable, Codable {
    struct MetadataChange: Hashable, Codable {
        enum Field: String, Codable {
            case name = "group_name", unknown
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
            "\(creator.displayName) added and removed members from the group"
        } else if !addedMembers.isEmpty {
            "\(creator.displayName) added \(addedMembers.formattedNamesString) to the group"
        } else if !removedMembers.isEmpty {
            "\(creator.displayName) removed \(removedMembers.formattedNamesString) from the group"
        } else if let metadataChange = metadataChanges.first,
                  metadataChange.field == .name,
                  let updatedName = metadataChange.newValue {
            "\(creator.displayName) changed the group name to \"\(updatedName)\""
        } else {
            "Unknown update"
        }
    }
}
