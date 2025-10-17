import ConvosCore
import Foundation

extension Invite {
    var inviteURLString: String {
        "https://\(ConfigManager.shared.associatedDomain)/\(urlSlug)"
    }
    var inviteURL: URL? {
        return URL(string: inviteURLString)
    }
}
