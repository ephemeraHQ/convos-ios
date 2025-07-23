import Combine
import SwiftUI
import UIKit

class MessagesContainerViewController: UIViewController {
    let contentView: UIView = UIView()
    let messagesInputView: InputHostingController<MessagesInputView>
    private var conversationCancellable: AnyCancellable?

    // MARK: - First Responder Management

    var shouldBecomeFirstResponder: Bool = true

    override var inputAccessoryView: UIView? {
        messagesInputView
    }

    override var canResignFirstResponder: Bool {
        true
    }

    override var canBecomeFirstResponder: Bool {
        true
    }

    // MARK: - Conversation

    private var conversationRepositoryCancellable: AnyCancellable?
    private let conversationState: ConversationState
    private let outgoingMessageWriter: any OutgoingMessageWriterProtocol
    private let conversationLocalStateWriter: any ConversationLocalStateWriterProtocol

    // MARK: - Init

    init(conversationState: ConversationState,
         messagesInputViewModel: MessagesInputViewModel,
         outgoingMessageWriter: any OutgoingMessageWriterProtocol,
         conversationLocalStateWriter: any ConversationLocalStateWriterProtocol,
         dismissAction: DismissAction) {
        self.conversationState = conversationState
        self.outgoingMessageWriter = outgoingMessageWriter
        self.conversationLocalStateWriter = conversationLocalStateWriter
        self.messagesInputView = InputHostingController(
            rootView: MessagesInputView(
                viewModel: messagesInputViewModel,
                conversationState: conversationState
            )
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        conversationRepositoryCancellable?.cancel()
    }

    // MARK: - Actions

    private func markConversationAsRead() {
        Task {
            do {
                try await conversationLocalStateWriter.setUnread(
                    false,
                    for: conversationState.conversationId
                )
            } catch {
                Logger.error("Failed marking conversation as read: \(error)")
            }
        }
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if shouldBecomeFirstResponder {
            shouldBecomeFirstResponder = false
            becomeFirstResponderAfterTransitionCompletes()
        }

        markConversationAsRead()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        resignFirstResponderAfterTransitionCompletes()
        markConversationAsRead()
    }

    // MARK: - UI Setup

    private func setupUI() {
        setupInputBar()
        view.backgroundColor = .clear
        contentView.backgroundColor = .clear
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentView)

        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: view.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupInputBar() {
        messagesInputView.translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: - Child VC Embedding

    func embedContentController(_ child: UIViewController) {
        addChild(child)
        child.view.backgroundColor = .clear
        contentView.addSubview(child.view)
        child.view.frame = contentView.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        child.didMove(toParent: self)
    }
}
