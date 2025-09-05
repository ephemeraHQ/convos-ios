import ConvosCore
import Foundation
import SwiftUI

enum DeepLinkDestination {
    case requestToJoin(inviteCode: String)
    // Future: case viewJoinRequests(inviteCode: String) for inviters to see pending requests
}

@Observable
final class DeepLinkHandler {
    var pendingDeepLink: DeepLinkDestination?
    var shouldPresentRequestToJoin: Bool = false
    var inviteCodeToProcess: String?

    func handleURL(_ url: URL) -> Bool {
        // Validate both appscheme://join/code and https://domain.com/join/code
        let isValidScheme = url.scheme == "https" ?
            url.host == ConfigManager.shared.associatedDomain :
            url.scheme == ConfigManager.shared.appUrlScheme

        return isValidScheme ? extractInviteCode(from: url) : false
    }

    private func extractInviteCode(from url: URL) -> Bool {
        // Handle both formats:
        // Format 1: convos-local://join/code (host="join", pathComponents=["code"])
        // Format 2: https://domain.com/join/code (host="domain.com", pathComponents=["join", "code"])

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        var inviteCode: String?

        if url.host == "join" && !pathComponents.isEmpty {
            // App scheme: convos-local://join/code
            inviteCode = pathComponents[0]
        } else if pathComponents.count >= 2 && pathComponents[0] == "join" {
            // Universal link: https://domain.com/join/code
            inviteCode = pathComponents[1]
        } else {
            return false
        }

        guard let inviteCode = inviteCode, !inviteCode.isEmpty else {
            return false
        }

        updatePendingState(inviteCode: inviteCode)
        return true
    }

    func clearPendingDeepLink() {
        pendingDeepLink = nil
        inviteCodeToProcess = nil
        shouldPresentRequestToJoin = false
    }

    // MARK: - Private Methods

    private func updatePendingState(inviteCode: String) {
        pendingDeepLink = .requestToJoin(inviteCode: inviteCode)
        inviteCodeToProcess = inviteCode
        shouldPresentRequestToJoin = true
    }
}
