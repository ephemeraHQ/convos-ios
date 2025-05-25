import SwiftUI
import UIKit

class MessagesNavigationBar: UIView {
    // MARK: - Properties

    private let blurView: UIVisualEffectView = UIVisualEffectView(
        effect: UIBlurEffect(style: .regular)
    )
    private(set) var viewModel: MessagesToolbarViewModel = MessagesToolbarViewModel()
    private var hostingController: UIHostingController<MessagesToolbarView>?

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public Methods

    func configure(conversation: Conversation?,
                   placeholderTitle: String = "",
                   subtitle: String? = nil) {
        viewModel.conversation = conversation
        viewModel.placeholderTitle = placeholderTitle
        viewModel.subtitle = subtitle
    }

    // MARK: - Private Methods

    private func setupUI() {
        backgroundColor = .white.withAlphaComponent(0.8)
        blurView.layer.borderWidth = 0
        blurView.layer.backgroundColor = UIColor.clear.cgColor
        blurView.layer.masksToBounds = false
        blurView.layer.shadowColor = UIColor.systemGray5.cgColor
        blurView.layer.shadowOffset = CGSize(width: 0, height: 1)
        blurView.layer.shadowOpacity = 1
        blurView.layer.shadowRadius = 0

        addSubview(blurView)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let swiftUIView = MessagesToolbarView(viewModel: viewModel)
        let hostingController = UIHostingController(rootView: swiftUIView)
        hostingController.view.backgroundColor = .clear
        self.hostingController = hostingController

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }
}
