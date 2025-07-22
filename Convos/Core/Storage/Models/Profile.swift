import Foundation
import GRDB

struct Profile: Codable, Identifiable, Hashable {
    var id: String { inboxId }
    let inboxId: String
    let name: String?
    let username: String?
    let avatar: String?

    var avatarURL: URL? {
        guard let avatar, let url = URL(string: avatar) else {
            return nil
        }
        return url
    }

    var displayName: String {
        name ?? "Someone"
    }

    static var empty: Profile {
        .init(
            inboxId: UUID().uuidString,
            name: nil,
            username: nil,
            avatar: nil
        )
    }
}

// MARK: - Array Extensions

extension Array where Element == Profile {
    var formattedNamesString: String {
        let displayNames = self.map { $0.displayName }
            .filter { !$0.isEmpty }
            .sorted()

        switch displayNames.count {
        case 0:
            return ""
        case 1:
            return displayNames[0]
        case 2:
            return displayNames.joined(separator: " & ")
        default:
            let allButLast = displayNames.dropLast().joined(separator: ", ")
            let last = displayNames.last ?? ""
            return "\(allButLast) and \(last)"
        }
    }
}
