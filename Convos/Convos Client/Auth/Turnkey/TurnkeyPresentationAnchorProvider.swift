import AuthenticationServices
import UIKit

/// Shared utility for providing presentation anchors in Turnkey services
@MainActor
final class TurnkeyPresentationAnchorProvider {

    /// Gets the current window for presentation anchor
    /// - Throws: TurnkeyPresentationAnchorError.failedFindingPasskeyPresentationAnchor if no window is found
    static func presentationAnchor() throws -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            throw TurnkeyPresentationAnchorError.failedFindingPasskeyPresentationAnchor
        }

        return window
    }
}

/// Error types for presentation anchor operations
enum TurnkeyPresentationAnchorError: Error {
    case failedFindingPasskeyPresentationAnchor
}
