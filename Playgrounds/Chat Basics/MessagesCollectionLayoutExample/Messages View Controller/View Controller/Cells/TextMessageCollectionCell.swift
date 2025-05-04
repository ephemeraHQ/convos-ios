import UIKit
import SwiftUI

class TextMessageCollectionCell: UICollectionViewCell {

    // MARK: - Properties

    private var message: String = ""
    private var messageType: MessageType = .incoming
    private var bubbleStyle: Cell.BubbleType = .normal
    private var longPressGestureRecognizer: UILongPressGestureRecognizer?
    private weak var reactionMenuController: MessageReactionMenuController?

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

    // MARK: - Gesture Handling

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            showReactionMenu()

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
            }

        case .ended, .cancelled:
            if let reactionMenu = reactionMenuController {
                reactionMenu.animateOut { [weak self] in
                    self?.reactionMenuController?.dismiss(animated: false)
                    self?.reactionMenuController = nil
                }
            }

        default:
            break
        }
    }

    private func showReactionMenu() {
        guard let window else { return }

        // Get the exact frame of the cell's content in window coordinates
        let cellFrame = convert(contentView.frame, to: window)

        let config = MessageReactionMenuController.Configuration(
            sourceCell: self,
            sourceRect: cellFrame,
            containerView: window
        )

        let reactionMenu = MessageReactionMenuController(configuration: config)
        window.rootViewController?.present(reactionMenu, animated: true)
        self.reactionMenuController = reactionMenu
    }
}

// MARK: - PreviewableCell

extension TextMessageCollectionCell: PreviewableCell {
    func previewView() -> UIView? {
        // Create an image view with a snapshot of our current content
        let renderer = UIGraphicsImageRenderer(bounds: contentView.bounds)
        let image = renderer.image { context in
            contentView.drawHierarchy(in: contentView.bounds, afterScreenUpdates: true)
        }

        let imageView = UIImageView(image: image)
        imageView.frame = contentView.frame
        imageView.contentMode = .scaleToFill
        return imageView
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
