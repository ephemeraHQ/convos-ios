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
        // Handle both URL schemes (convos-local://) and universal links (https://)
        if url.scheme?.hasPrefix("convos") == true {
            return handleCustomScheme(url)
        } else if url.scheme == "https" {
            return handleUniversalLink(url)
        }
        return false
    }

    private func handleCustomScheme(_ url: URL) -> Bool {
        return processJoinPath(from: url)
    }

    private func handleUniversalLink(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host else {
            return false
        }

        let validDomain = ConfigManager.shared.associatedDomain
        guard host == validDomain else {
            return false
        }

        return processJoinPath(from: url)
    }

    private func processJoinPath(from url: URL) -> Bool {
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard !pathComponents.isEmpty else {
            return false
        }
        // Handle invite code redemption (request to join)
        // URL format: [scheme]://[domain]/join/[inviteCode]
        if pathComponents[0] == "join" && pathComponents.count > 1 {
            let inviteCode = pathComponents[1]
            updatePendingState(inviteCode: inviteCode)
            return true
        }
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
