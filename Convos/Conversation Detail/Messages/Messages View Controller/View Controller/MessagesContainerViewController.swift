import Combine
import SwiftUI
import UIKit

class MessagesContainerViewController: UIViewController {
    let navigationBar: MessagesToolbarViewHost
    let contentView: UIView = UIView()
    let messagesInputView: MessagesInputView
    private var joinConversationInputView: InputHostingController<JoinConversationInputView>
    private var navigationBarHeightConstraint: NSLayoutConstraint?
    private var conversationCancellable: AnyCancellable?

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
         sendMessage: @escaping () -> Void,
         textBinding: Binding<String>,
         joinConversation: @escaping () -> Void,
         deleteConversation: @escaping () -> Void) {
        self.conversationState = conversationState
        self.outgoingMessageWriter = outgoingMessageWriter
        self.conversationConsentWriter = conversationConsentWriter
        self.conversationLocalStateWriter = conversationLocalStateWriter
        self.navigationBar = MessagesToolbarViewHost(
            conversationState: conversationState,
            dismissAction: dismissAction
        )
        self.messagesInputView = MessagesInputView(sendMessage: sendMessage)
        self.joinConversationInputView = .init(
            rootView: JoinConversationInputView(
                onJoinConversation: joinConversation,
                onDeleteConversation: deleteConversation
            )
        )
        super.init(nibName: nil, bundle: nil)
        conversationCancellable = conversationState
            .conversationPublisher
            .receive(on: DispatchQueue.main)
            .withPrevious()
            .sink { [weak self] previous, current in
                guard let self else { return }
                guard previous?.consent != current?.consent else { return }
                reloadInputViews()
            }
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
        messagesInputView.translatesAutoresizingMaskIntoConstraints = false
        joinConversationInputView.translatesAutoresizingMaskIntoConstraints = false
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
}

// MARK: - Keyboard

extension MessagesContainerViewController: KeyboardListenerDelegate {
    func keyboardWillHide(info: KeyboardInfo) {
        becomeFirstResponder()
    }
}
