import AuthenticationServices

/// Protocol for providing a presentation anchor for passkey authentication
public protocol PasskeyPresentationContextProvider: ASAuthorizationControllerPresentationContextProviding {
    /// The window or view that should be used to present the passkey authentication UI
    var presentationAnchor: ASPresentationAnchor { get }
}

// Default implementation for ASAuthorizationControllerPresentationContextProviding
public extension PasskeyPresentationContextProvider {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return presentationAnchor
    }
}
