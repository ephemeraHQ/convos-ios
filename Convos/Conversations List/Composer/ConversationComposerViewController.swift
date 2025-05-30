import SwiftUI
import UIKit

class ConversationComposerViewController: UIViewController {
    let messagesViewController: MessagesViewController
    let profileSearchRepository: any ProfileSearchRepositoryProtocol
    private let composerHostingController: UIHostingController<ConversationComposerContentView>

    init(
        messagesRepository: any MessagesRepositoryProtocol,
        outgoingMessageWriter: any OutgoingMessageWriterProtocol,
        profileSearchRepository: any ProfileSearchRepositoryProtocol,
    ) {
        self.messagesViewController = MessagesViewController(
            outgoingMessageWriter: outgoingMessageWriter,
            messagesRepository: messagesRepository
        )
        self.profileSearchRepository = profileSearchRepository
        let composerView = ConversationComposerContentView(
            profileSearchRepository: profileSearchRepository
        )
        let hosting = UIHostingController(rootView: composerView)
        self.composerHostingController = hosting
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationController?.setNavigationBarHidden(true, animated: false)

        addChild(messagesViewController)
        view.addSubview(messagesViewController.view)
        messagesViewController.view.frame = view.bounds
        messagesViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        messagesViewController.didMove(toParent: self)

        composerHostingController.navigationController?.setNavigationBarHidden(true, animated: false)
        addChild(composerHostingController)
        messagesViewController.view.insertSubview(composerHostingController.view,
                                                  aboveSubview: messagesViewController.collectionView)
        composerHostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            composerHostingController.view.leadingAnchor.constraint(
                equalTo: messagesViewController.view.safeAreaLayoutGuide.leadingAnchor
            ),
            composerHostingController.view.trailingAnchor.constraint(
                equalTo: messagesViewController.view.safeAreaLayoutGuide.trailingAnchor
            ),
            composerHostingController.view.topAnchor.constraint(
                equalTo: messagesViewController.navigationBar.bottomAnchor
            ),
            composerHostingController.view.bottomAnchor.constraint(
                equalTo: messagesViewController.view.safeAreaLayoutGuide.bottomAnchor
            )
        ])
        composerHostingController.didMove(toParent: self)
    }

    func animateComposerOut(completion: (() -> Void)? = nil) {
        UIView.animate(withDuration: 0.3, animations: { [weak self] in
            guard let self else { return }
            composerHostingController.view.alpha = 0
        }, completion: { [weak self] _ in
            guard let self else { return }
            composerHostingController.willMove(toParent: nil)
            composerHostingController.view.removeFromSuperview()
            composerHostingController.removeFromParent()
            completion?()
        })
    }
}
