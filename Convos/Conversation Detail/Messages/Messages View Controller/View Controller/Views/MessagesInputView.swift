import SwiftUI
import UIKit

// MARK: - MessagesInputViewDelegate

protocol MessagesInputViewDelegate: AnyObject {
    func messagesInputView(_ view: MessagesInputView, didChangeText text: String)
}

// MARK: - MessagesInputView

final class MessagesInputView: UIView {
    weak var delegate: MessagesInputViewDelegate?
    private var keyboardIsShowing: Bool = false
    private var textViewHeightConstraint: NSLayoutConstraint?
    private let sendMessage: () -> Void

    // MARK: - UI Components

    private lazy var glassView: UIVisualEffectView = {
        let glassEffect = UIGlassEffect()
        let view = UIVisualEffectView(effect: glassEffect)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private(set) lazy var textView: UITextView = {
        let tv = UITextView()
        tv.font = .systemFont(ofSize: Constant.textViewFontSize)
        tv.textColor = UIColor.colorTextPrimary
        tv.backgroundColor = .clear
        tv.textContainerInset = Constant.textViewInset
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.isScrollEnabled = false
        tv.delegate = self
        return tv
    }()

    lazy var sendButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        button.tintColor = .colorBackgroundInverted
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(handleSendButtonTap), for: .touchUpInside)
        return button
    }()

    // MARK: - Initialization

    var text: String {
        get {
            textView.text
        }
        set {
            textView.text = newValue
        }
    }

    var sendButtonEnabled: Bool {
        get {
            sendButton.isEnabled
        }
        set {
            sendButton.isEnabled = newValue
        }
    }

    init(
        sendMessage: @escaping () -> Void
    ) {
        self.sendMessage = sendMessage
        super.init(frame: .zero)
        setupView()
        setupNotifications()
        setupKeyboardListener()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View Setup

    private func setupView() {
        configureBackground()
        addSubviews()
        setupConstraints()
    }

    private func configureBackground() {
        backgroundColor = .clear
    }

    private func addSubviews() {
        [glassView, textView, sendButton].forEach { addSubview($0) }
    }

    private func setupConstraints() {
        setupTextViewHeightConstraint()
        setupLayoutConstraints()
    }

    private func setupTextViewHeightConstraint() {
        textViewHeightConstraint = textView.heightAnchor.constraint(equalToConstant: Constant.baseHeight)
        textViewHeightConstraint?.isActive = true
    }

    private func setupLayoutConstraints() {
        NSLayoutConstraint.activate([
            // Glass View Constraints
            glassView.topAnchor.constraint(equalTo: textView.topAnchor),
            glassView.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: textView.trailingAnchor),
            glassView.bottomAnchor.constraint(equalTo: textView.bottomAnchor),

            // Text View Constraints
            textView.topAnchor.constraint(equalTo: topAnchor, constant: Constant.margin),
            textView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: Constant.margin),
            textView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -Constant.margin),

            // Send Button Constraints
            sendButton.bottomAnchor.constraint(equalTo: textView.bottomAnchor),
            sendButton.trailingAnchor.constraint(equalTo: textView.trailingAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: Constant.sendButtonSize),
            sendButton.heightAnchor.constraint(equalToConstant: Constant.sendButtonSize)
        ])
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTextChange),
            name: UITextView.textDidChangeNotification,
            object: textView
        )
    }

    private func setupKeyboardListener() {
        KeyboardListener.shared.add(delegate: self)
    }

    deinit {
        KeyboardListener.shared.remove(delegate: self)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        updateTextViewCornerRadius()
    }

    private func updateTextViewCornerRadius() {
        let shouldUseRoundedCorners = textViewHeightConstraint?.constant == Constant.baseHeight || textView.text.isEmpty
        glassView.layer.cornerRadius = shouldUseRoundedCorners
            ? glassView.frame.height / 2.0
            : Constant.textViewCornerRadius
    }

    override var intrinsicContentSize: CGSize {
        let textHeight = (textViewHeightConstraint?.constant ?? Constant.baseHeight) + (Constant.margin * 2.0)
        return CGSize(width: UIView.noIntrinsicMetric, height: textHeight + safeAreaInsets.bottom)
    }

    // MARK: - First Responder

    override var canBecomeFirstResponder: Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        textView.becomeFirstResponder()
    }

    // MARK: - Actions

    @objc private func handleTextChange() {
        updateTextViewHeight()
        invalidateIntrinsicContentSize()
    }

    private func updateTextViewHeight() {
        let size = CGSize(width: textView.bounds.width, height: .infinity)
        let estimatedSize = textView.sizeThatFits(size)
        let newHeight = min(max(estimatedSize.height, Constant.baseHeight), Constant.maxHeight)
        textViewHeightConstraint?.constant = newHeight
    }

    @objc private func handleSendButtonTap() {
        guard let text = textView.text, !text.isEmpty else { return }

        sendMessage()
        clearTextView()
    }

    private func clearTextView() {
        textView.text = ""
        handleTextChange()
        delegate?.messagesInputView(self, didChangeText: textView.text)
    }

    enum Constant {
        static let bottomInset: CGFloat = 14.0
        static let margin: CGFloat = 14.0
        static let sendButtonSize: CGFloat = 36.0
        static let baseHeight: CGFloat = 36.0
        static let maxHeight: CGFloat = 150.0
        static let textViewCornerRadius: CGFloat = 16.0
        static let textViewFontSize: CGFloat = 16.0
        static let textViewInset: UIEdgeInsets = UIEdgeInsets(top: 8,
                                                              left: 12,
                                                              bottom: 8,
                                                              right: sendButtonSize)
    }
}

// MARK: - KeyboardListenerDelegate

extension MessagesInputView: KeyboardListenerDelegate {
    func keyboardWillShow(info: KeyboardInfo) {
        invalidateIntrinsicContentSize()
    }

    func keyboardWillHide(info: KeyboardInfo) {
        invalidateIntrinsicContentSize()
    }

    func keyboardWillChangeFrame(info: KeyboardInfo) {
        keyboardIsShowing = info.frameEnd.height >= intrinsicContentSize.height
        invalidateIntrinsicContentSize()
    }
}

// MARK: - UITextViewDelegate

extension MessagesInputView: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        delegate?.messagesInputView(self, didChangeText: textView.text)
    }
}
