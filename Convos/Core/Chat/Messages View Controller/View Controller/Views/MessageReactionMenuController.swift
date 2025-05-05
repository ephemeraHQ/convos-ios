import UIKit

class MessageReactionMenuController: UIViewController {
    struct Configuration {
        enum Edge {
            case leading, trailing
        }

        let sourceCell: PreviewableCollectionViewCell
        let sourceRect: CGRect
        let containerView: UIView
        let sourceCellEdge: Edge
        let startColor: UIColor
    }

    // MARK: - Positioning Constants
    private static let topInset: CGFloat = 116
    private static let betweenInset: CGFloat = 56
    private static let spacing: CGFloat = 8.0 // You can adjust this if you want extra space
    // between the betweenInset and the previewView

    // MARK: - Properties

    private let configuration: Configuration
    let dimmingView: UIVisualEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
    private let previewContainerView: UIView = UIView()
    let previewView: UIView
    let previewSourceView: UIView
    let actualPreviewSourceSize: CGSize
    let endPosition: CGRect
    private var animator: UIViewPropertyAnimator?
    private var panGestureRecognizer: UIPanGestureRecognizer?
    let shapeView: ReactionMenuShapeView
    private var previewPanHandler: PreviewViewPanHandler?

    // MARK: - Initialization

    init(configuration: Configuration) {
        self.configuration = configuration
        self.previewView = configuration.sourceCell.previewView()
        self.previewSourceView = configuration.sourceCell.previewSourceView
        self.actualPreviewSourceSize = configuration.sourceCell.actualPreviewSourceSize
        self.previewView.frame = configuration.sourceRect
        self.endPosition = MessageReactionMenuController.calculateEndPosition(
            for: self.previewView,
            in: configuration.containerView,
            sourceRect: configuration.sourceRect
        )

        // Create initial shape view
        let startSize = CGSize(width: 56, height: 56)
        let startFrame = CGRect(origin: .zero, size: startSize)
        self.shapeView = ReactionMenuShapeView(frame: startFrame)
        self.shapeView.fillColor = configuration.startColor

        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .custom
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - End Position Helper

    private static func calculateEndPosition(
        for previewView: UIView,
        in containerView: UIView,
        sourceRect: CGRect
    ) -> CGRect {
        let topInset = Self.topInset + containerView.safeAreaInsets.top
        let betweenInset = Self.betweenInset
        let spacing = Self.spacing
        let minY = topInset + betweenInset + spacing
        let maxY = containerView.bounds.height - previewView.bounds.height - containerView.safeAreaInsets.bottom
        let desiredY = min(max(sourceRect.origin.y, minY), maxY)
        let finalX = (containerView.bounds.width - previewView.bounds.width) / 2
        return CGRect(x: finalX, y: desiredY, width: previewView.bounds.width, height: previewView.bounds.height)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        let horizontalInset = configuration.sourceCell.horizontalInset
        let leftMargin: CGFloat = 24.0
        let rightMargin: CGFloat = 56.0
        let endWidth = view.bounds.width - leftMargin - rightMargin - horizontalInset
        let endHeight: CGFloat = 56.0

        let xPosition: CGFloat
        switch configuration.sourceCellEdge {
        case .leading:
            xPosition = view.bounds.minX + (horizontalInset / 2.0) + endHeight
        case .trailing:
            xPosition = view.bounds.minX + view.bounds.maxX - (endHeight * 2.0) - (horizontalInset / 2.0)
        }

        let yPosition = endPosition.minY - Self.spacing - endHeight

        let targetFrame = CGRect(x: xPosition, y: yPosition, width: endWidth, height: endHeight)
        shapeView.animateToShape(frame: targetFrame, color: .systemBackground)

        // Attach pan handler to previewView
        previewPanHandler = PreviewViewPanHandler(containerView: view) { [weak self] in
            guard let self else { return nil }
            return previewView
        }
        previewPanHandler?.onShouldDismiss = { [weak self] in
            self?.startInteractiveDismiss()
        }
    }

    private func startInteractiveDismiss() {
        // Start your interactive dismiss transition here
        dismiss(animated: true, completion: nil)
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        setupViews()
    }

    // MARK: - Setup

    private func setupViews() {
        view.backgroundColor = .clear

        dimmingView.frame = view.bounds
        dimmingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(dimmingView)

        // Position shape view
        let horizontalInset = configuration.sourceCell.horizontalInset
        let previewFrame = configuration.sourceRect
        let endHeight = 56.0

        // Decide which corner to use
        let xPosition: CGFloat
        switch configuration.sourceCellEdge {
        case .leading:
            xPosition = view.bounds.minX + (horizontalInset / 2.0) + endHeight
        case .trailing:
            xPosition = view.bounds.minX + view.bounds.maxX - (endHeight * 2.0) - (horizontalInset / 2.0)
        }

        let yPosition = previewFrame.minY - Self.spacing - endHeight
        let startRect = CGRect(
            x: xPosition,
            y: yPosition + endHeight + Self.spacing,
            width: endHeight,
            height: endHeight
        )

        shapeView.frame = startRect
        shapeView.configureShadow()
        view.addSubview(shapeView)

        // Setup preview container
        previewContainerView.frame = view.bounds
        previewContainerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        previewContainerView.backgroundColor = .clear
        view.addSubview(previewContainerView)
    }
}
