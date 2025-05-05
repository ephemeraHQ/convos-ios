import UIKit

protocol MessageReactionMenuCoordinatorDelegate: AnyObject {
    func messageReactionMenuCoordinator(_ coordinator: MessageReactionMenuCoordinator, previewableCellAt indexPath: IndexPath) -> PreviewableCollectionViewCell?
    func messageReactionMenuCoordinator(_ coordinator: MessageReactionMenuCoordinator, shouldPresentMenuFor cell: PreviewableCollectionViewCell) -> Bool
    func messageReactionMenuCoordinatorDidBeginTransition(_ coordinator: MessageReactionMenuCoordinator)
    func messageReactionMenuCoordinatorDidEndTransition(_ coordinator: MessageReactionMenuCoordinator)
    var collectionView: UICollectionView { get }
}

class MessageReactionMenuCoordinator: UIPercentDrivenInteractiveTransition {
    weak var delegate: MessageReactionMenuCoordinatorDelegate?

    private var panHandler: PreviewViewPanHandler?
    private var doubleTapRecognizer: UITapGestureRecognizer!
    private var longPressRecognizer: UILongPressGestureRecognizer!

    // Store context for transition
    private var transitionSourceCell: PreviewableCollectionViewCell?
    private var transitionSourceRect: CGRect?
    private var transitionContainerView: UIView?
    private weak var currentMenuController: MessageReactionMenuController?

    // Interactive transition state
    private var isInteractive = false
    private var initialTouchPoint: CGPoint = .zero
    private var initialViewCenter: CGPoint = .zero
    private var interactivePreviewView: UIView?
    private var interactiveMenuController: MessageReactionMenuController?
    private var interactiveDirection: TransitionDirection = .presentation
    private var displayLink: CADisplayLink?
    private var gestureStartTime: CFTimeInterval = 0
    private static let activationDuration: TimeInterval = 0.4
    private enum TransitionDirection { case presentation, dismissal }

    init(delegate: MessageReactionMenuCoordinatorDelegate) {
        self.delegate = delegate
        super.init()
        setupGestureRecognizers()
    }

    private func setupGestureRecognizers() {
        guard let collectionView = delegate?.collectionView else { return }

        // Set up long press for interactive presentation
        longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressRecognizer.delegate = self
        longPressRecognizer.minimumPressDuration = 0.2
        collectionView.addGestureRecognizer(longPressRecognizer)

        // Set up double tap
        doubleTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTapRecognizer.numberOfTapsRequired = 2
        doubleTapRecognizer.delegate = self
        collectionView.addGestureRecognizer(doubleTapRecognizer)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard let collectionView = delegate?.collectionView else { return }
        let location = gesture.location(in: collectionView)
        switch gesture.state {
            case .began:
                guard let indexPath = collectionView.indexPathForItem(at: location),
                      let cell = delegate?.messageReactionMenuCoordinator(self, previewableCellAt: indexPath),
                      delegate?.messageReactionMenuCoordinator(self, shouldPresentMenuFor: cell) ?? true else {
                    return
                }

                let cellRect = cell.convert(cell.bounds, to: collectionView.window)

                // Set up interactive state
                isInteractive = true
                initialTouchPoint = location
                interactiveDirection = .presentation

                presentMenu(for: cell, at: cellRect, edge: cell.sourceCellEdge, interactive: true)
                initialViewCenter = interactivePreviewView?.center ?? cell.center

                delegate?.messageReactionMenuCoordinatorDidBeginTransition(self)

                gestureStartTime = CACurrentMediaTime()
                displayLink = CADisplayLink(target: self, selector: #selector(handleDisplayLinkTick))
                displayLink?.add(to: .main, forMode: .common)

            case .ended, .cancelled, .failed:
                if displayLink != nil {
                    finish()
                } else {
                    cancel()
                }
                
                delegate?.messageReactionMenuCoordinatorDidEndTransition(self)
            default:
                break
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        guard let collectionView = delegate?.collectionView else { return }
        let location = gesture.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: location),
              let cell = delegate?.messageReactionMenuCoordinator(self, previewableCellAt: indexPath) else { return }
        let cellRect = cell.convert(cell.bounds, to: collectionView.window)
        guard delegate?.messageReactionMenuCoordinator(self, shouldPresentMenuFor: cell) ?? true else { return }
        presentMenu(for: cell, at: cellRect, edge: cell.sourceCellEdge, interactive: false)
    }

    private func presentMenu(for cell: PreviewableCollectionViewCell,
                             at rect: CGRect,
                             edge: MessageReactionMenuController.Configuration.Edge,
                             interactive: Bool = false) {
        guard let window = delegate?.collectionView.window else { return }
        let config = MessageReactionMenuController.Configuration(
            sourceCell: cell,
            sourceRect: rect,
            containerView: window,
            sourceCellEdge: edge,
            startColor: UIColor(hue: 0.0, saturation: 0.0, brightness: 0.96, alpha: 1.0)
        )
        let menuController = MessageReactionMenuController(configuration: config)
        menuController.modalPresentationStyle = .custom
        menuController.transitioningDelegate = self

        transitionSourceCell = cell
        transitionSourceRect = rect
        transitionContainerView = window
        currentMenuController = menuController

        if interactive {
            interactiveMenuController = menuController
            interactivePreviewView = menuController.previewView
        }

        window.rootViewController?.present(menuController, animated: true)
    }

    @objc private func handleDisplayLinkTick() {
        guard isInteractive else { return }
        let elapsed = CACurrentMediaTime() - gestureStartTime
        let progress = min(elapsed / Self.activationDuration, 1.0)
        self.update(CGFloat(progress))
        if progress >= 1.0 {
            let feedback = UIImpactFeedbackGenerator(style: .medium)
            feedback.impactOccurred(at: interactivePreviewView?.center ?? .zero)

            finish()
        }
    }

    internal override func finish() {
        displayLink?.invalidate()
        displayLink = nil
        resetInteractiveState()
        super.finish()
    }

    internal override func cancel() {
        displayLink?.invalidate()
        displayLink = nil
        resetInteractiveState()
        super.cancel()
    }

    private func resetInteractiveState() {
        isInteractive = false
        interactivePreviewView = nil
        interactiveMenuController = nil
    }

    func interactionControllerForPresentation(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        return isInteractive ? self : nil
    }

    func interactionControllerForDismissal(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        return isInteractive ? self : nil
    }
}

extension MessageReactionMenuCoordinator: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
//        // Allow pan and long press to work together
//        if (gestureRecognizer is UILongPressGestureRecognizer && otherGestureRecognizer is UIPanGestureRecognizer) ||
//            (gestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer is UILongPressGestureRecognizer) {
//            return true
//        }
//
//        if gestureRecognizer is UIPanGestureRecognizer {
//            return true
//        }

        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer is UILongPressGestureRecognizer,
           otherGestureRecognizer is UITapGestureRecognizer {
            return true
        }

        return false
    }
}

extension MessageReactionMenuCoordinator: UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard let cell = transitionSourceCell, let rect = transitionSourceRect else { return nil }
        return MessageReactionPresentationAnimator(sourceCell: cell, sourceRect: rect)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard let cell = transitionSourceCell, let rect = transitionSourceRect else { return nil }
        return MessageReactionDismissalAnimator(sourceCell: cell, sourceRect: rect)
    }
}

final class MessageReactionPresentationAnimator: NSObject, UIViewControllerAnimatedTransitioning, CAAnimationDelegate {
    private let sourceCell: PreviewableCollectionViewCell
    private let sourceRect: CGRect

    static var activationDuration: CGFloat = 0.25

    init(sourceCell: PreviewableCollectionViewCell, sourceRect: CGRect) {
        self.sourceCell = sourceCell
        self.sourceRect = sourceRect
        super.init()
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        MessageReactionPresentationAnimator.activationDuration + 0.01
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let toVC = transitionContext.viewController(forKey: .to) as? MessageReactionMenuController else {
            transitionContext.completeTransition(false)
            return
        }

        let containerView = transitionContext.containerView
        let finalFrame = transitionContext.finalFrame(for: toVC)
        toVC.view.frame = finalFrame

        let previewView = toVC.previewView
        previewView.layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)

        toVC.previewSourceView.alpha = 0.0
        containerView.addSubview(toVC.view)
        containerView.addSubview(previewView)

        toVC.view.alpha = 0.0

        let duration = transitionDuration(using: transitionContext)
        let overshootScale: CGFloat = 1.02

        UIView.animateKeyframes(withDuration: duration,
                                delay: 0,
                                options: [.calculationModeCubic, .beginFromCurrentState], animations: {
            UIView.addKeyframe(withRelativeStartTime: 0.0, relativeDuration: 0.9) {
                guard !transitionContext.transitionWasCancelled else {
                    transitionContext.completeTransition(false)
                    return
                }

                previewView.transform = CGAffineTransform(scaleX: overshootScale, y: overshootScale)
                previewView.layer.shadowOpacity = 0.15
                previewView.layer.shadowRadius = 10.0
                previewView.layer.shadowOffset = .zero
            }

            UIView.addKeyframe(withRelativeStartTime: 1.0, relativeDuration: 0.4) {
                guard !transitionContext.transitionWasCancelled else {
                    transitionContext.completeTransition(false)
                    return
                }

                toVC.dimmingView.alpha = 1.0
                toVC.view.alpha = 1.0
            }

        }, completion: { finished in

            UIView.animate(withDuration: 0.5,
                           delay: 0.0,
                           usingSpringWithDamping: 0.8,
                           initialSpringVelocity: 0.2,
                           options: .beginFromCurrentState) {
                previewView.transform = .identity
                previewView.frame = toVC.endPosition
            } completion: { finished in
                previewView.removeFromSuperview()
                toVC.view.addSubview(previewView)
            }
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        })
    }
}

final class MessageReactionDismissalAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let sourceCell: PreviewableCollectionViewCell
    private let sourceRect: CGRect

    init(sourceCell: PreviewableCollectionViewCell, sourceRect: CGRect) {
        self.sourceCell = sourceCell
        self.sourceRect = sourceRect
        super.init()
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.35
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let fromVC = transitionContext.viewController(forKey: .from) as? MessageReactionMenuController else {
            transitionContext.completeTransition(false)
            return
        }

        let containerView = transitionContext.containerView

        let previewView = fromVC.previewView
        previewView.frame = sourceRect
        containerView.addSubview(previewView)

        let duration = transitionDuration(using: transitionContext)

        UIView.animate(withDuration: duration,
                       delay: 0,
                       options: [.curveEaseInOut, .beginFromCurrentState]) {
            fromVC.view.alpha = 0.0
            fromVC.dimmingView.alpha = 0.0
            previewView.alpha = 0.0
            previewView.transform = .identity
            previewView.layer.shadowColor = UIColor.clear.cgColor
            previewView.layer.shadowOffset = .zero
            previewView.layer.shadowOpacity = 0.0
            previewView.layer.shadowRadius = 0
        } completion: { _ in
            fromVC.previewSourceView.alpha = 1.0
            previewView.removeFromSuperview()
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        }
    }
}
