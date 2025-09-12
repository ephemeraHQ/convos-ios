import Foundation

extension URL {
    public var convosInviteCode: String? {
        // Handle formats:
        // Format 1: convos://code (host=code for direct invite codes)
        // Format 2: https://domain.com/code (host="domain.com", pathComponents=["code"])

        let pathComponents = pathComponents.filter { $0 != "/" }
        var inviteCode: String?

        if scheme?.hasPrefix("convos") == true {
            // App scheme: convos://code or convos-dev://code
            if let host = host, !host.isEmpty {
                inviteCode = host
            }
        } else if scheme == "https" {
            // Universal link: https://domain.com/code
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
