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
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host else {
            return false
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }

        guard !pathComponents.isEmpty else {
            return false
        }

        let validDomain = ConfigManager.shared.associatedDomain

        guard host == validDomain else {
            return false
        }

        // Handle invite code redemption (request to join)
        // URL format: https://domain.com/join/[inviteCode]
        if pathComponents[0] == "join" && pathComponents.count > 1 {
            let inviteCode = pathComponents[1]
            updatePendingState(inviteCode: inviteCode)
            return true
        }

        // Future: Handle viewing join requests for inviters
        // URL format: https://domain.com/requests/[inviteCode]

        return false
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
