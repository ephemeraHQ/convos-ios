import UIKit
import AuthenticationServices
import PasskeyAuth

@objc
final class PasskeyPresentationProvider: NSObject, PasskeyPresentationContextProvider {
    let presentationAnchor: ASPresentationAnchor
    
    override init() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            fatalError("No window found")
        }
        self.presentationAnchor = window
        super.init()
    }
    
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        self.presentationAnchor
    }
} 
