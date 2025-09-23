import ConvosCore
import Foundation
import SwiftUI

enum DeepLinkDestination {
    case requestToJoin(inviteCode: String)
}

final class DeepLinkHandler {
    static func destination(for url: URL) -> DeepLinkDestination? {
        let isValidScheme = url.scheme == "https" ?
            isValidHost(url.host) :
            url.scheme == ConfigManager.shared.appUrlScheme

        guard isValidScheme else {
            Logger.warning("Dismissing deep link with invalid scheme")
            return nil
        }

        guard let inviteCode = url.convosInviteCode else {
            Logger.warning("Deep link is missing invite code")
            return nil
        }

        return .requestToJoin(inviteCode: inviteCode)
    }

    private static func isValidHost(_ host: String?) -> Bool {
        guard let host = host else {
            Logger.warning("Deep link is missing host")
            return false
        }

        // Check against the configured associated domain
        return host == ConfigManager.shared.associatedDomain
    }
}
