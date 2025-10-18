import Foundation

extension URL {
    public var convosInviteCode: String? {
        // Handle formats:
        // Format 1: convos://join/invite-code (app scheme)
        // Format 2: https://domain.com/v2?i=invite-code (universal link)

        var inviteCode: String?

        if scheme?.hasPrefix("convos") == true {
            // App scheme: convos://join/invite-code
            let pathComponents = pathComponents.filter { $0 != "/" }
            if host == "join" && pathComponents.count >= 1 {
                inviteCode = pathComponents[0]
            }
        } else if scheme == "https" {
            // Universal link: https://domain.com/v2?i=invite-code
            if let components = URLComponents(url: self, resolvingAgainstBaseURL: false),
               path.contains("/v2"),
               let queryItems = components.queryItems,
               let inviteQueryItem = queryItems.first(where: { $0.name == "i" }),
               let code = inviteQueryItem.value {
                inviteCode = code
            }
        }

        guard let inviteCode = inviteCode, !inviteCode.isEmpty else {
            return nil
        }

        return inviteCode
    }
}
