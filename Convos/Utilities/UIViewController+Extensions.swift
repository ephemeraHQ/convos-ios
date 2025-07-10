import UIKit

extension UIViewController {
    func becomeFirstResponderAfterTransitionCompletes() {
        setFirstResponderAfterTransitionCompletes(shouldBecome: true)
    }

    func resignFirstResponderAfterTransitionCompletes() {
        if let coordinator = transitionCoordinator {
            // Resign before transition begins
            resignFirstResponder()
            coordinator.animate(alongsideTransition: nil) { _ in
                // No additional action needed after transition
            }
        } else {
            // No transition in progress, resign immediately
            resignFirstResponder()
        }
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
