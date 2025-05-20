import SwiftUI
import UIKit

class ConversationComposerViewController: UIViewController {
    let messagesViewController: MessagesViewController
    let messagingService: any ConvosSDK.MessagingServiceProtocol
    private var composerHostingController: UIHostingController<ConversationComposerContentView>?

    init(
        messagesStore: MessagesStoreProtocol,
        messagingService: any ConvosSDK.MessagingServiceProtocol
    ) {
        self.messagesViewController = MessagesViewController(messagesStore: messagesStore)
        self.messagingService = messagingService
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

        let composerView = ConversationComposerContentView(messagingService: messagingService)
        let hosting = UIHostingController(rootView: composerView)
        hosting.navigationController?.setNavigationBarHidden(true, animated: false)
        addChild(hosting)
        messagesViewController.view.insertSubview(hosting.view,
                                                  aboveSubview: messagesViewController.collectionView)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(
                equalTo: messagesViewController.view.safeAreaLayoutGuide.leadingAnchor
            ),
            hosting.view.trailingAnchor.constraint(
                equalTo: messagesViewController.view.safeAreaLayoutGuide.trailingAnchor
            ),
            hosting.view.topAnchor.constraint(
                equalTo: messagesViewController.navigationBar.bottomAnchor
            ),
            hosting.view.bottomAnchor.constraint(
                equalTo: messagesViewController.view.safeAreaLayoutGuide.bottomAnchor
            )
        ])
        hosting.didMove(toParent: self)
        self.composerHostingController = hosting
    }

    func animateComposerOut(completion: (() -> Void)? = nil) {
        guard let composer = composerHostingController else { completion?(); return }
        UIView.animate(withDuration: 0.3, animations: {
            composer.view.alpha = 0
        }, completion: { _ in
            composer.willMove(toParent: nil)
            composer.view.removeFromSuperview()
            composer.removeFromParent()
            completion?()
        })
    }
}
