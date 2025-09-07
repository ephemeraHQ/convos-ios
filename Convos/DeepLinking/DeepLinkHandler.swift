import ConvosCore
import Foundation
import SwiftUI

enum DeepLinkDestination {
    case requestToJoin(inviteCode: String)
}

final class DeepLinkHandler {
    static func destination(for url: URL) -> DeepLinkDestination? {
        let isValidScheme = url.scheme == "https" ?
            url.host == ConfigManager.shared.associatedDomain :
            url.scheme == ConfigManager.shared.appUrlScheme

        guard isValidScheme else {
            return nil
        }

        guard let inviteCode = url.convosInviteCode else {
            return nil
        }

        return .requestToJoin(inviteCode: inviteCode)
    }
}
