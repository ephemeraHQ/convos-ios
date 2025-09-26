import ConvosCore
import Foundation

extension Invite {
    var inviteURLString: String {
        "https://\(ConfigManager.shared.associatedDomain)/\(inviteSlug)"
    }
    var inviteURL: URL? {
        return URL(string: inviteURLString)
    }
}
