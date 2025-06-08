import Combine
import SwiftUI
import UIKit

extension UIViewController {
    func becomeFirstResponderAfterTransitionCompletes() {
        if let coordinator = transitionCoordinator {
            coordinator.animate(alongsideTransition: nil) { _ in
                DispatchQueue.main.async { [weak self] in
                    self?.becomeFirstResponder()
                }
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.becomeFirstResponder()
            }
        }
    }
}

class ConversationComposerViewController: UIViewController {
    let messagesContainerViewController: MessagesContainerViewController
    let profileSearchRepository: any ProfileSearchRepositoryProtocol
    private let composerHostingController: UIHostingController<ConversationComposerContentView>
    private var cancellables: Set<AnyCancellable> = []

    init(
        composerState: ConversationComposerState,
        profileSearchRepository: any ProfileSearchRepositoryProtocol,
    ) {
        self.messagesContainerViewController = MessagesContainerViewController(
            conversationRepository: composerState.draftConversationRepo,
            outgoingMessageWriter: composerState.draftConversationWriter,
            conversationConsentWriter: composerState.conversationConsentWriter,
            conversationLocalStateWriter: composerState.conversationLocalStateWriter
        )
        messagesContainerViewController.delegate = composerState
        self.profileSearchRepository = profileSearchRepository
        let composerView = ConversationComposerContentView(
            composerState: composerState
        )
        let hosting = UIHostingController(rootView: composerView)
        self.composerHostingController = hosting
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        messagesContainerViewController.shouldBecomeFirstResponder = false
        addChild(messagesContainerViewController)
        view.addSubview(messagesContainerViewController.view)
        messagesContainerViewController.view.frame = view.bounds
        messagesContainerViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        messagesContainerViewController.didMove(toParent: self)

        messagesContainerViewController.embedContentController(composerHostingController)
    }
}

extension ConversationComposerState: MessagesContainerViewControllerDelegate {
    func messagesContainerViewControllerDidSendMessage(_ viewController: MessagesContainerViewController) {
        didSendMessage()
    }
}
