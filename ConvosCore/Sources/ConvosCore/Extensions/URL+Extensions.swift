import Foundation

extension URL {
    public var convosInviteCode: String? {
        // Handle both formats:
        // Format 1: convos-local://join/code (host="join", pathComponents=["code"])
        // Format 2: https://domain.com/join/code (host="domain.com", pathComponents=["join", "code"])

        let pathComponents = pathComponents.filter { $0 != "/" }
        var inviteCode: String?

        if host == "join" && !pathComponents.isEmpty {
            // App scheme: convos-local://join/code
            inviteCode = pathComponents[0]
        } else if pathComponents.count >= 2 && pathComponents[0] == "join" {
            // Universal link: https://domain.com/join/code
            inviteCode = pathComponents[1]
        } else {
            return nil
        }

        guard let inviteCode = inviteCode, !inviteCode.isEmpty else {
            return nil
        }

        return inviteCode
    }
}
