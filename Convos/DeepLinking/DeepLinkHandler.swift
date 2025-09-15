import ConvosCore
import Foundation
import SwiftUI

enum DeepLinkDestination {
    case joinConversation(inviteCode: String)
}

final class DeepLinkHandler {
    static func destination(for url: URL) -> DeepLinkDestination? {
        let isValidScheme = url.scheme == "https" ?
            isValidHost(url.host) :
            url.scheme == ConfigManager.shared.appUrlScheme

        guard isValidScheme else {
            return nil
        }

        guard let inviteCode = url.convosInviteCode else {
            return nil
        }

        return .joinConversation(inviteCode: inviteCode)
    }

    private static func isValidHost(_ host: String?) -> Bool {
        guard let host = host else { return false }

        // Check against the configured associated domain
        return host == ConfigManager.shared.associatedDomain
    }
}
