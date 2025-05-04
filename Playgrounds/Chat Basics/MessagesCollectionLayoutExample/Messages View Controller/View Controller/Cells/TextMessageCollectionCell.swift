import UIKit
import SwiftUI

class TextMessageCollectionCell: UICollectionViewCell {

    // MARK: - Properties

    private var message: String = ""
    private var messageType: MessageType = .incoming
    private var bubbleStyle: Cell.BubbleType = .normal
    private var longPressGestureRecognizer: UILongPressGestureRecognizer?
    private weak var reactionMenuController: MessageReactionMenuController?

    // Preview state
    private var cachedPreviewView: UIView?
    private var gestureStartTime: Date?
    private var activationTimer: Timer?
    private let activationDuration: TimeInterval = 0.8
    private var feedbackGenerator: UIImpactFeedbackGenerator?

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupGestureRecognizers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGestureRecognizers()
    }

    private func setupGestureRecognizers() {
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.0
        addGestureRecognizer(longPress)
        longPressGestureRecognizer = longPress
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.contentConfiguration = nil
        message = ""
        messageType = .incoming
        bubbleStyle = .normal
        cleanupPreviewState()
    }

    func setup(message: String, messageType: MessageType, style: Cell.BubbleType) {
        self.message = message
        self.messageType = messageType
        self.bubbleStyle = style

        contentConfiguration = UIHostingConfiguration {
            VStack(alignment: .leading) {
                MessageBubble(style: style,
                              message: message,
                              isOutgoing: messageType == .outgoing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .margins(.vertical, 0.0)
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        layoutAttributesForHorizontalFittingRequired(layoutAttributes)
    }

    // MARK: - Preview Handling

    private func showInitialPreview() {
        guard let window = window,
              cachedPreviewView == nil else { return }


        guard let previewView = previewView() else { return }
        self.cachedPreviewView = previewView
        window.addSubview(previewView)

        // Prepare haptic feedback
        feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        feedbackGenerator?.prepare()

        // Start tracking time
        gestureStartTime = Date()

        // Start timer for activation
        activationTimer = Timer.scheduledTimer(withTimeInterval: activationDuration, repeats: false) { [weak self] _ in
            self?.activateReactionMenu()
        }

        // Animate initial shadow
        UIView.animate(withDuration: 0.3) {
            previewView.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
            previewView.layer.shadowColor = UIColor.black.cgColor
            previewView.layer.shadowOffset = .zero
            previewView.layer.shadowOpacity = 0.5
            previewView.layer.shadowRadius = 10

        }
    }

    private func activateReactionMenu() {
        guard let window = window else { return }

        // Trigger haptic feedback
        feedbackGenerator?.impactOccurred()
        feedbackGenerator = nil

        let config = MessageReactionMenuController.Configuration(
            sourceCell: self,
            sourceRect: cachedPreviewView?.frame ?? convert(bounds, to: window),
            containerView: window
        )

        let reactionMenu = MessageReactionMenuController(configuration: config)
        window.rootViewController?.present(reactionMenu, animated: true)
        self.reactionMenuController = reactionMenu

        // Remove our preview since the menu controller will create its own
        cleanupPreviewState()
    }

    private func cleanupPreviewState() {
        activationTimer?.invalidate()
        activationTimer = nil
        gestureStartTime = nil
        feedbackGenerator = nil

        UIView.animate(withDuration: 0.2, animations: {
            self.cachedPreviewView?.transform = .identity
        }) { _ in
            self.cachedPreviewView?.removeFromSuperview()
            self.cachedPreviewView = nil
        }
    }

    // MARK: - Gesture Handling

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            showInitialPreview()

        case .changed:
            if let reactionMenu = reactionMenuController {
                let location = gesture.location(in: gesture.view)
                let translation = CGPoint(
                    x: location.x - gesture.view!.bounds.width / 2.0,
                    y: location.y - gesture.view!.bounds.height / 2.0
                )
                let panGesture = UIPanGestureRecognizer(target: nil, action: nil)
                panGesture.state = .changed
                panGesture.setTranslation(translation, in: reactionMenu.view)
                reactionMenu.handlePanGesture(panGesture)
            } else if let preview = cachedPreviewView {
                // Update preview position if menu hasn't shown yet
//                let translation = gesture.translation(in: window)
//                preview.transform = CGAffineTransform(translationX: translation.x, y: translation.y)
//                    .scaledBy(x: 1.05, y: 1.05)
            }

        case .ended, .cancelled:
            if let reactionMenu = reactionMenuController {
                reactionMenu.animateOut { [weak self] in
                    self?.reactionMenuController?.dismiss(animated: false)
                    self?.reactionMenuController = nil
                }
            } else {
                cleanupPreviewState()
            }

        default:
            break
        }
    }
}

// MARK: - PreviewableCell

extension TextMessageCollectionCell: PreviewableCell {
    func previewView() -> UIView? {
        guard let window else { return nil }

        layoutIfNeeded()

        let convertedFrame = convert(contentView.frame, to: window)

        // Create the snapshot
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = window.screen.scale
        format.preferredRange = .extended

        let renderer = UIGraphicsImageRenderer(bounds: contentView.bounds, format: format)
        let image = renderer.image { context in
            contentView.drawHierarchy(in: contentView.bounds, afterScreenUpdates: true)
        }

        let preview = UIView(frame: convertedFrame)
        preview.layer.contents = image.cgImage
        preview.clipsToBounds = false
        return preview
    }
}

struct MessageBubble: View {
    let style: Cell.BubbleType
    let message: String
    let isOutgoing: Bool

    var body: some View {
        HStack {
            MessageContainer(style: style,
                             isOutgoing: isOutgoing) {
                Text(message)
                    .foregroundColor(isOutgoing ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

            }
        }
    }
}

#Preview {
    VStack {
        ForEach([MessageType.outgoing, MessageType.incoming], id: \.self) { type in
            MessageBubble(style: .normal,
                message: "Hello world!", isOutgoing: type == .outgoing)
        }
    }
}
