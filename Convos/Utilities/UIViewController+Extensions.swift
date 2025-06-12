import UIKit

extension UIViewController {
    func becomeFirstResponderAfterTransitionCompletes() {
        if let coordinator = transitionCoordinator {
            coordinator.animate(alongsideTransition: nil) { _ in
                DispatchQueue.main.async { [weak self] in
                    self?.becomeFirstResponder()
                }
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.becomeFirstResponder()
            }
        }
    }
}
