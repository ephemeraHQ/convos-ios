import UIKit

extension UIViewController {
    func becomeFirstResponderAfterTransitionCompletes() {
        setFirstResponderAfterTransitionCompletes(shouldBecome: true)
    }

    func resignFirstResponderAfterTransitionCompletes() {
        setFirstResponderAfterTransitionCompletes(shouldBecome: false)
    }

    private func setFirstResponderAfterTransitionCompletes(shouldBecome: Bool) {
        if let coordinator = transitionCoordinator {
            coordinator.animate(alongsideTransition: nil) { _ in
                DispatchQueue.main.async { [weak self] in
                    if shouldBecome {
                        self?.becomeFirstResponder()
                    } else {
                        self?.resignFirstResponder()
                    }
                }
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                if shouldBecome {
                    self?.becomeFirstResponder()
                } else {
                    self?.resignFirstResponder()
                }
            }
        }
    }
}
