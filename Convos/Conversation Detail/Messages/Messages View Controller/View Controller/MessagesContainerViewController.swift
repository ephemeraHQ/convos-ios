import Combine
import SwiftUI
import UIKit

protocol MessagesContainerViewControllerDelegate: AnyObject {
    func messagesContainerViewControllerDidSendMessage(_ viewController: MessagesContainerViewController)
}

class MessagesContainerViewController: UIViewController, JoinConversationInputViewModelType {
    weak var delegate: MessagesContainerViewControllerDelegate?

    // MARK: - Interface Actions

    private enum ReactionTypes {
        case delayedUpdate
    }

    private enum InterfaceActions {
        case sendingMessage
    }

    private var currentInterfaceActions: SetActor<Set<InterfaceActions>, ReactionTypes> = SetActor()

    // MARK: - UI Components

    let navigationBar: MessagesToolbarViewHost
    let contentView: UIView = UIView()
    private let messagesInputView: MessagesInputView
    private var joinConversationInputView: JoinConversationInputHostingController?
    private var navigationBarHeightConstraint: NSLayoutConstraint?

    // MARK: - First Responder Management

    var shouldBecomeFirstResponder: Bool = true

    override var inputAccessoryView: UIView? {
        guard let conversation = conversationState.conversation,
              !conversation.isDraft else {
            return messagesInputView
        }
        switch conversation.consent {
        case .allowed:
            return messagesInputView
        case .denied:
            return nil
        case .unknown:
            return joinConversationInputView
        }
    }

    override var canBecomeFirstResponder: Bool {
        true
    }

    // MARK: - Conversation

    private var conversationRepositoryCancellable: AnyCancellable?
    private let conversationState: ConversationState
    private let outgoingMessageWriter: any OutgoingMessageWriterProtocol
    private let conversationConsentWriter: any ConversationConsentWriterProtocol
    private let conversationLocalStateWriter: any ConversationLocalStateWriterProtocol

    // MARK: - Init

    init(conversationState: ConversationState,
         outgoingMessageWriter: any OutgoingMessageWriterProtocol,
         conversationConsentWriter: any ConversationConsentWriterProtocol,
         conversationLocalStateWriter: any ConversationLocalStateWriterProtocol,
         dismissAction: DismissAction,
         textBinding: Binding<String>,
         sendButtonEnabled: Binding<Bool>) {
        self.conversationState = conversationState
        self.outgoingMessageWriter = outgoingMessageWriter
        self.conversationConsentWriter = conversationConsentWriter
        self.conversationLocalStateWriter = conversationLocalStateWriter
        self.navigationBar = MessagesToolbarViewHost(
            conversationState: conversationState,
            dismissAction: dismissAction
        )
        self.messagesInputView = MessagesInputView(
            textBinding: textBinding,
            sendButtonEnabled: sendButtonEnabled
        )
        super.init(nibName: nil, bundle: nil)
        self.joinConversationInputView = .init(viewModel: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        conversationRepositoryCancellable?.cancel()
        KeyboardListener.shared.remove(delegate: self)
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
        KeyboardListener.shared.add(delegate: self)

        _ = withObservationTracking {
            conversationState.conversation
        } onChange: {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                updateSendButtonEnabled(for: conversationState.conversation)
                reloadInputViews()
            }
        }
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

        markConversationAsRead()
    }

    // MARK: - UI Setup

    private func setupUI() {
        setupInputBar()
        view.addSubview(navigationBar)
        navigationBar.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .colorBackgroundPrimary
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentView)

        let heightConstraint = navigationBar.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            navigationBar.topAnchor.constraint(equalTo: view.topAnchor),
            navigationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            heightConstraint,
            contentView.topAnchor.constraint(equalTo: navigationBar.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        registerForTraitChanges(
            [UITraitVerticalSizeClass.self]
        ) { (self: Self, _: UITraitCollection) in
            self.updateNavigationBarHeight(heightConstraint)
        }

        updateNavigationBarHeight(heightConstraint)
        navigationBarHeightConstraint = heightConstraint
    }

    private func setupInputBar() {
        messagesInputView.delegate = self
        messagesInputView.translatesAutoresizingMaskIntoConstraints = false
        joinConversationInputView?.translatesAutoresizingMaskIntoConstraints = false
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        if let constraint = navigationBarHeightConstraint {
            updateNavigationBarHeight(constraint)
        }
    }

    private func updateNavigationBarHeight(_ constraint: NSLayoutConstraint) {
        let baseHeight = traitCollection.verticalSizeClass == .compact ?
        MessagesToolbarView.Constant.compactHeight :
        MessagesToolbarView.Constant.regularHeight
        constraint.constant = baseHeight + view.safeAreaInsets.top
    }

    // MARK: - JoinConversationInputViewDelegate

    func joinConversation() {
        guard let conversation = conversationState.conversation else { return }
        Task {
            do {
                try await conversationConsentWriter.join(conversation: conversation)
            } catch {
                Logger.error("Error joining conversation: \(error)")
            }
        }
    }

    func deleteConversation() {
        guard let conversation = conversationState.conversation else { return }
        navigationController?.popViewController(animated: true)
        Task {
            do {
                try await conversationConsentWriter.delete(conversation: conversation)
            } catch {
                Logger.error("Error deleting conversation: \(error)")
            }
        }
    }

    // MARK: - Child VC Embedding

    func embedContentController(_ child: UIViewController) {
        addChild(child)
        contentView.addSubview(child.view)
        child.view.frame = contentView.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        child.didMove(toParent: self)
    }

    // MARK: - Private

    private func updateSendButtonEnabled(for conversation: Conversation?) {
        let conversationHasMembers: Bool = !(conversation?.members.isEmpty ?? true)
        let enabled = conversationHasMembers && !messagesInputView.textView.text.isEmpty
        messagesInputView.sendButton.isEnabled = enabled
        messagesInputView.sendButton.alpha = enabled ? 1 : 0.2
    }
}

// MARK: - Keyboard

extension MessagesContainerViewController: KeyboardListenerDelegate {
    func keyboardWillHide(info: KeyboardInfo) {
        becomeFirstResponder()
    }
}

// MARK: - MessagesInputViewDelegate

extension MessagesContainerViewController: MessagesInputViewDelegate {
    func messagesInputView(_ view: MessagesInputView, didChangeIntrinsicContentSize size: CGSize) {
        guard !currentInterfaceActions.options.contains(.sendingMessage) else { return }
        //        scrollToBottom()
    }

    func messagesInputView(_ view: MessagesInputView, didTapSend text: String) {
        currentInterfaceActions.options.insert(.sendingMessage)
        delegate?.messagesContainerViewControllerDidSendMessage(self)
        if let messagesVC = children.first(where: { $0 is MessagesViewController }) as? MessagesViewController {
            messagesVC.scrollToBottom()
        }
        Task {
            do {
                try await outgoingMessageWriter.send(text: text)
            } catch {
                Logger.error("Error sending message: \(error)")
            }
            currentInterfaceActions.options.remove(.sendingMessage)
        }
    }

    func messagesInputView(_ view: MessagesInputView, didChangeText text: String) {
        updateSendButtonEnabled(for: conversationState.conversation)
    }
}
