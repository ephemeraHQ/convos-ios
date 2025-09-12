import Foundation

extension URL {
    public var convosInviteCode: String? {
        // Handle formats:
        // Format 1: convos://join/invite-code (app scheme with host="join", pathComponents=["invite-code"])
        // Format 2: https://domain.com/invite-code (universal link with pathComponents=["invite-code"])

        let pathComponents = pathComponents.filter { $0 != "/" }
        var inviteCode: String?

        if scheme?.hasPrefix("convos") == true {
            // App scheme: convos://join/invite-code
            if host == "join" && pathComponents.count >= 1 {
                inviteCode = pathComponents[0]
            }
        } else if scheme == "https" {
            // Universal link: https://domain.com/invite-code
            if pathComponents.count == 1 {
                inviteCode = pathComponents[0]
            }
        }

        guard let inviteCode = inviteCode, !inviteCode.isEmpty else {
            return nil
        }

        return inviteCode
    }
}
