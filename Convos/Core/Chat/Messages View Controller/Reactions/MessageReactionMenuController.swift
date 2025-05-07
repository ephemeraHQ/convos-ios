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

        // Positioning Constants
        static let topInset: CGFloat = 116.0
        static let betweenInset: CGFloat = 56.0
        static let maxPreviewHeight: CGFloat = 75.0
        static let spacing: CGFloat = 8.0
        static let shapeViewHeight: CGFloat = 56.0
        static let leftMargin: CGFloat = 24.0
        static let rightMargin: CGFloat = shapeViewHeight

        var shapeViewStartingRect: CGRect {
            let horizontalInset = sourceCell.horizontalInset
            let previewFrame = sourceRect
            let endSize = Self.shapeViewHeight
            let startSize = min(endSize, previewFrame.height)
            let view = containerView
            let xPosition: CGFloat
            switch sourceCellEdge {
            case .leading:
                xPosition = view.bounds.minX + (horizontalInset / 2.0)
            case .trailing:
                xPosition = view.bounds.minX + view.bounds.maxX - startSize - (horizontalInset / 2.0)
            }
            let yPosition = previewFrame.minY
            return CGRect(
                x: xPosition,
                y: yPosition,
                width: endSize,
                height: startSize
            )
        }

        var endPosition: CGRect {
            let topInset = Self.topInset + containerView.safeAreaInsets.top
            let betweenInset = Self.betweenInset
            let spacing = Self.spacing
            let minY = topInset + betweenInset + spacing
            let maxY = containerView.bounds.midY - min(Self.maxPreviewHeight, sourceRect.height)
            let desiredY = min(max(sourceRect.origin.y, minY), maxY < 0.0 ? minY : maxY)
            let finalX = (containerView.bounds.width - sourceRect.width) / 2
            return CGRect(x: finalX, y: desiredY, width: sourceRect.width, height: sourceRect.height)
        }

        var shapeViewEndingRect: CGRect {
            let yPosition = endPosition.minY - Self.spacing - shapeViewStartingRect.height
            var targetFrame = shapeViewStartingRect
            let horizontalInset = sourceCell.horizontalInset
            let endWidth = containerView.bounds.width - Self.leftMargin - Self.rightMargin - horizontalInset
            let endHeight = Self.shapeViewHeight
            targetFrame.size.width = endWidth
            targetFrame.origin.y = yPosition - (endHeight - shapeViewStartingRect.height)
            targetFrame.size.height = endHeight
            if sourceCellEdge == .trailing {
                targetFrame.origin.x -= (endWidth - shapeViewStartingRect.width)
            }
            return targetFrame
        }
    }

    enum ReactionsViewSize {
        case expanded,
             collapsed,
             compact
    }

    // MARK: - Properties

    let configuration: Configuration
    let actualPreviewSourceSize: CGSize
    let shapeViewStartingRect: CGRect
    let endPosition: CGRect
    private var shapeViewEndingRect: CGRect?

    let dimmingView: UIVisualEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
    let previewView: UIView
    let shapeView: ReactionMenuShapeView
    let previewSourceView: UIView

    fileprivate let reactionsVC: ReactionsViewController
    private var tapGestureRecognizer: UITapGestureRecognizer?
    private var panGestureRecognizer: UIPanGestureRecognizer?
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
        self.shapeViewStartingRect = configuration.shapeViewStartingRect
        self.endPosition = configuration.endPosition

        // Create initial shape view
        let startSize = CGSize(width: Configuration.shapeViewHeight, height: Configuration.shapeViewHeight)
        let startFrame = CGRect(origin: .zero, size: startSize)
        self.shapeView = ReactionMenuShapeView(frame: startFrame)
        self.shapeView.fillColor = configuration.startColor

        self.reactionsVC = ReactionsViewController(viewModel: viewModel)

        super.init(nibName: nil, bundle: nil)

        viewModel.isCollapsedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isCollapsed in
                guard let self else { return }
                animateShapeView(to: isCollapsed ? .collapsed : .expanded)
            }
            .store(in: &cancellables)

        viewModel.selectedEmojiPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] selectedEmoji in
                guard let self else { return }
                if selectedEmoji != nil {
                    animateShapeView(to: .compact)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.dismiss(animated: true)
                    }
                }
            }
            .store(in: &cancellables)

        self.tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))

        modalPresentationStyle = .custom
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - End Position Helper

    private func animateShapeView(to size: ReactionsViewSize) {
        guard let shapeViewEndingRect else { return }
        var shapeRect = shapeView.frame
        switch size {
        case .expanded:
            shapeRect.size.width = shapeViewEndingRect.width
        case .collapsed:
            shapeRect.size.width = shapeViewStartingRect.width * 2.0
        case .compact:
            shapeRect.size.width = shapeViewStartingRect.width + (Configuration.spacing * 2.0)
        }
        shapeView.animateToShape(frame: shapeRect,
                                 alpha: 1.0,
                                 color: .systemBackground)
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

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        shapeView.animateToShape(frame: shapeViewStartingRect,
                                 alpha: 0.0,
                                 color: .systemBackground)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        shapeViewEndingRect = configuration.shapeViewEndingRect
        shapeView.animateToShape(frame: configuration.shapeViewEndingRect,
                                 alpha: 1.0,
                                 color: .systemBackground)

        // Attach pan handler to previewView
        previewPanHandler = PreviewViewPanHandler(containerView: view) { [weak self] in
            guard let self else { return nil }
            return previewView
        }
        previewPanHandler?.onShouldDismiss = { [weak self] in
            self?.dismiss(animated: true)
        }
    }

    // MARK: - Setup

    private func setupViews() {
        view.backgroundColor = .clear

        dimmingView.frame = view.bounds
        dimmingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(dimmingView)

        if let tapGestureRecognizer {
            dimmingView.addGestureRecognizer(tapGestureRecognizer)
        }

        shapeView.frame = shapeViewStartingRect
        shapeView.configureShadow()
        view.addSubview(shapeView)

        addChild(reactionsVC)
        shapeView.addSubview(reactionsVC.view)
        reactionsVC.didMove(toParent: self)
    }

    // MARK: - Gestures

    @objc private func handleTap() {
        dismiss(animated: true)
    }
}
