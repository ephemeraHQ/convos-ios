import Combine
import SwiftUI
import UIKit

class MessagesContainerViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let contentView: UIView = UIView()
    let messagesInputView: InputHostingController<MessagesInputView>
    private let messagesInputViewModel: MessagesInputViewModel
    private var showingImagePicker: Bool = false

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
        self.messagesInputViewModel = messagesInputViewModel
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

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        if messagesInputViewModel.showingPhotosPicker && !showingImagePicker {
            self.presentImagePicker()
        }
    }

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

    // MARK: - Photo Picker

    private func presentImagePicker() {
        showingImagePicker = true
        let imagePicker = UIImagePickerController()
        imagePicker.delegate = self
        imagePicker.sourceType = .photoLibrary
        imagePicker.mediaTypes = ["public.image"]
        imagePicker.allowsEditing = false
        present(imagePicker, animated: true) { [weak self] in
            // @jarodl this is a hack to get around the editor hiding when the keyboard is dismissed from this modal
            self?.messagesInputViewModel.showingProfileNameEditor = true
        }
    }

    // MARK: - UIImagePickerControllerDelegate

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true) { [weak self] in
            self?.showingImagePicker = false
            self?.messagesInputViewModel.showingPhotosPicker = false
            self?.messagesInputViewModel.showingProfileNameEditor = true
        }

        if let image = info[.originalImage] as? UIImage {
            messagesInputViewModel.imageSelection = image
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true) { [weak self] in
            self?.showingImagePicker = false
            self?.messagesInputViewModel.showingPhotosPicker = false
            self?.messagesInputViewModel.showingProfileNameEditor = true
        }
    }
}
