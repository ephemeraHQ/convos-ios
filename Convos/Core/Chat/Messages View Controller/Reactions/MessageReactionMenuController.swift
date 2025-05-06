import Combine
import SwiftUI
import UIKit

struct MessageReaction: Identifiable {
    let id: String
    let emoji: String
    let isSelected: Bool
}

private class ReactionsViewController: UIViewController {
    let hostingVC: UIHostingController<MessageReactionsView>

    var viewModel: MessageReactionMenuViewModel {
        didSet { update() }
    }

    init(viewModel: MessageReactionMenuViewModel) {
        self.viewModel = viewModel
        let reactionsView = MessageReactionsView(viewModel: viewModel)
        self.hostingVC = UIHostingController(rootView: reactionsView)
        self.hostingVC.sizingOptions = .intrinsicContentSize
        super.init(nibName: nil, bundle: nil)
        self.addChild(hostingVC)
        self.view.addSubview(hostingVC.view)
        hostingVC.didMove(toParent: self)
        self.view.layer.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        hostingVC.view.frame = view.bounds
    }

    func update() {
        hostingVC.rootView = MessageReactionsView(viewModel: viewModel)
    }
}

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

    let configuration: Configuration
    let dimmingView: UIVisualEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
    let previewView: UIView
    let previewSourceView: UIView
    let actualPreviewSourceSize: CGSize
    let shapeViewStartingRect: CGRect
    private var shapeViewEndingRect: CGRect?
    let endPosition: CGRect
    fileprivate let reactionsVC: ReactionsViewController
    private var animator: UIViewPropertyAnimator?
    private var panGestureRecognizer: UIPanGestureRecognizer?
    let shapeView: ReactionMenuShapeView
    private var previewPanHandler: PreviewViewPanHandler?
    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Initialization

    init(configuration: Configuration,
         viewModel: MessageReactionMenuViewModel) {
        self.configuration = configuration
        self.previewView = configuration.sourceCell.previewView()
        self.previewSourceView = configuration.sourceCell.previewSourceView
        self.actualPreviewSourceSize = configuration.sourceCell.actualPreviewSourceSize
        self.previewView.frame = configuration.sourceRect
        self.shapeViewStartingRect = Self.shapeViewStartRect(for: configuration)
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

        self.reactionsVC = ReactionsViewController(viewModel: viewModel)

        super.init(nibName: nil, bundle: nil)

        viewModel.isCollapsedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isCollapsed in
                guard let self else { return }
                animateShapeView(collapsed: isCollapsed)
            }
            .store(in: &cancellables)

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

        let yPosition = endPosition.minY - Self.spacing - shapeViewStartingRect.height
        var targetFrame = shapeViewStartingRect
        let horizontalInset = configuration.sourceCell.horizontalInset
        let leftMargin: CGFloat = 24.0
        let rightMargin: CGFloat = 56.0
        let endWidth = view.bounds.width - leftMargin - rightMargin - horizontalInset
        targetFrame.size.width = endWidth
        targetFrame.origin.y = yPosition
        if configuration.sourceCellEdge == .trailing {
            targetFrame.origin.x -= (endWidth - shapeViewStartingRect.width)
        }
        shapeViewEndingRect = targetFrame
        shapeView.animateToShape(frame: targetFrame,
                                 alpha: 1.0,
                                 color: .systemBackground)

        // Attach pan handler to previewView
        previewPanHandler = PreviewViewPanHandler(containerView: view) { [weak self] in
            guard let self else { return nil }
            return previewView
        }
        previewPanHandler?.onShouldDismiss = { [weak self] in
            self?.startInteractiveDismiss()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        shapeView.animateToShape(frame: shapeViewStartingRect,
                                 alpha: 0.0,
                                 color: .systemBackground)
    }

    private func animateShapeView(collapsed: Bool) {
        guard let shapeViewEndingRect else { return }
        var shapeRect = shapeView.frame
        shapeRect.size.width = collapsed ? (shapeViewStartingRect.width * 2.0) : shapeViewEndingRect.width
        shapeView.animateToShape(frame: shapeRect,
                                 alpha: 1.0,
                                 color: .systemBackground)
    }

    private func startInteractiveDismiss() {
        dismiss(animated: true, completion: nil)
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        setupViews()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        reactionsVC.view.frame = shapeView.bounds
        reactionsVC.view.layer.cornerRadius = shapeView.bounds.height / 2.0
    }

    // MARK: - Setup

    private static func shapeViewStartRect(for configuration: Configuration) -> CGRect {
        let horizontalInset = configuration.sourceCell.horizontalInset
        let previewFrame = configuration.sourceRect
        let endSize = 56.0

        let view = configuration.containerView

        // Decide which edge to use
        let xPosition: CGFloat
        switch configuration.sourceCellEdge {
        case .leading:
            xPosition = view.bounds.minX + (horizontalInset / 2.0)
        case .trailing:
            xPosition = view.bounds.minX + view.bounds.maxX - endSize - (horizontalInset / 2.0)
        }

        let yPosition = previewFrame.minY - Self.spacing - endSize
        let startRect = CGRect(
            x: xPosition,
            y: yPosition + endSize + Self.spacing,
            width: endSize,
            height: endSize
        )
        return startRect
    }

    private func setupViews() {
        view.backgroundColor = .clear

        dimmingView.frame = view.bounds
        dimmingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(dimmingView)

        shapeView.frame = shapeViewStartingRect
        shapeView.configureShadow()
        view.addSubview(shapeView)

        addChild(reactionsVC)
        shapeView.addSubview(reactionsVC.view)
        reactionsVC.didMove(toParent: self)
    }
}
