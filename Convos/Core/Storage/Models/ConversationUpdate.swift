import Foundation

struct ConversationUpdate: Hashable, Codable {
    let creator: Profile
    let addedMembers: [Profile]
    let removedMembers: [Profile]
    // add metadata fields

    var summary: String {
        if !addedMembers.isEmpty && !removedMembers.isEmpty {
            "\(creator.displayName) added and removed members from the group"
        } else if !addedMembers.isEmpty {
            "\(creator.displayName) added \(addedMembers.formattedNamesString) to the group"
        } else if !removedMembers.isEmpty {
            "\(creator.displayName) removed \(removedMembers.formattedNamesString) from the group"
        } else {
            "Unknown update"
        }
    }
}
