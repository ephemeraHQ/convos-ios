import UIKit

class MessageReactionMenuController: UIViewController {

    // MARK: - Types

    struct Configuration {
        let sourceCell: UICollectionViewCell & PreviewableCell
        let sourceRect: CGRect
        let containerView: UIView
    }

    // MARK: - Properties

    private let configuration: Configuration
    private let dimmingView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
    private let previewContainerView = UIView()
    private var previewView: UIView?
    private var initialPreviewFrame: CGRect = .zero
    private var animator: UIViewPropertyAnimator?

    // MARK: - Initialization

    init(configuration: Configuration) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupPreviewView()
        animateIn()
    }

    // MARK: - Setup

    private func setupViews() {
        view.backgroundColor = .clear

        // Setup dimming view
        dimmingView.alpha = 0
        dimmingView.frame = view.bounds
        dimmingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(dimmingView)

        // Setup preview container
        previewContainerView.frame = view.bounds
        previewContainerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        previewContainerView.backgroundColor = .clear
        view.addSubview(previewContainerView)
    }

    private func setupPreviewView() {
        guard let sourcePreviewView = configuration.sourceCell.previewView() else { return }

        // Create and position the preview view
        previewView = sourcePreviewView
        previewView?.frame = configuration.sourceRect

        if let previewView = previewView {
            previewContainerView.addSubview(previewView)
            initialPreviewFrame = configuration.sourceRect
        }
    }

    // MARK: - Animations

    private func animateIn() {
        // Calculate the center position maintaining the aspect ratio
        let targetScale: CGFloat = 1.0
        let scaledSize = CGSize(
            width: initialPreviewFrame.width * targetScale,
            height: initialPreviewFrame.height * targetScale
        )

        let targetX = (view.bounds.width - scaledSize.width) / 2
        let targetY = (view.bounds.height - scaledSize.height) / 2
        let targetFrame = CGRect(origin: CGPoint(x: targetX, y: targetY), size: scaledSize)

        self.previewView?.frame = initialPreviewFrame

        // Create animator
        animator = UIViewPropertyAnimator(duration: 0.8, dampingRatio: 0.8) {
            // Animate dimming view
            self.dimmingView.alpha = 1

            // Animate preview to center
//            self.previewView?.frame = targetFrame
        }

        animator?.startAnimation()
    }

    func animateOut(completion: @escaping () -> Void) {
        animator?.stopAnimation(true)

        animator = UIViewPropertyAnimator(duration: 0.3, dampingRatio: 1.0) {
            // Fade out dimming view
            self.dimmingView.alpha = 0

            // Animate preview back to original position
            self.previewView?.frame = self.initialPreviewFrame
        }

        animator?.addCompletion { _ in
            completion()
        }

        animator?.startAnimation()
    }

    // MARK: - Gesture Handling

    func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)

        switch gesture.state {
        case .changed:
            // Update preview position based on pan
            if let previewView = previewView {
                previewView.center = CGPoint(
                    x: previewView.center.x + translation.x,
                    y: previewView.center.y + translation.y
                )
            }
            gesture.setTranslation(.zero, in: view)

        case .ended, .cancelled:
            let shouldDismiss = abs(velocity.y) > 500 || abs(translation.y) > 200
            if shouldDismiss {
                animateOut { [weak self] in
                    self?.dismiss(animated: false)
                }
            } else {
                // Animate back to center
                animateIn()
            }

        default:
            break
        }
    }
}
