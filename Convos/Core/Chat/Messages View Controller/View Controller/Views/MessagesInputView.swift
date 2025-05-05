import UIKit

// MARK: - MessagesInputViewDelegate

protocol MessagesInputViewDelegate: AnyObject {
    func messagesInputView(_ view: MessagesInputView, didChangeText text: String)
    func messagesInputView(_ view: MessagesInputView, didTapSend text: String)
    func messagesInputView(_ view: MessagesInputView, didChangeIntrinsicContentSize size: CGSize)
}

// MARK: - MessagesInputView

final class MessagesInputView: UIView {
    // MARK: - Properties

    weak var delegate: MessagesInputViewDelegate?
    private var keyboardIsShowing: Bool = false
    private var textViewHeightConstraint: NSLayoutConstraint?

    // MARK: - UI Components

    private lazy var blurView: UIVisualEffectView = {
        let blurEffect = UIBlurEffect(style: .regular)
        let view = UIVisualEffectView(effect: blurEffect)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private(set) lazy var textView: UITextView = {
        let tv = UITextView()
        tv.font = .systemFont(ofSize: Constant.textViewFontSize)
        tv.backgroundColor = .white
        tv.layer.masksToBounds = true
        tv.layer.borderWidth = 1
        tv.layer.borderColor = UIColor.systemGray6.cgColor
        tv.textContainerInset = Constant.textViewInset
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.isScrollEnabled = false
        tv.delegate = self
        return tv
    }()

    private lazy var sendButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        button.tintColor = .black
        button.translatesAutoresizingMaskIntoConstraints = false
        button.alpha = 0.0
        button.addTarget(self, action: #selector(handleSendButtonTap), for: .touchUpInside)
        return button
    }()

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
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
        backgroundColor = .white.withAlphaComponent(0.8)
    }

    private func addSubviews() {
        [blurView, textView, sendButton].forEach { addSubview($0) }
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
            // Blur View Constraints
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Text View Constraints
            textView.topAnchor.constraint(equalTo: topAnchor, constant: Constant.margin),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constant.margin),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constant.margin),

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
        let shouldUseRoundedCorners = textViewHeightConstraint?.constant == Constant.baseHeight
        || textView.text.isEmpty
        textView.layer.cornerRadius = shouldUseRoundedCorners
        ? textView.frame.height / 2.0
        : Constant.textViewCornerRadius
    }

    override var intrinsicContentSize: CGSize {
        let textHeight = (textViewHeightConstraint?.constant ?? Constant.baseHeight) + (Constant.margin * 2.0)
        return CGSize(width: UIView.noIntrinsicMetric, height: textHeight + safeAreaInsets.bottom)
    }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        delegate?.messagesInputView(self, didChangeIntrinsicContentSize: intrinsicContentSize)
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
        updateSendButtonVisibility()
        invalidateIntrinsicContentSize()
    }

    private func updateTextViewHeight() {
        let size = CGSize(width: textView.bounds.width, height: .infinity)
        let estimatedSize = textView.sizeThatFits(size)
        let newHeight = min(max(estimatedSize.height, Constant.baseHeight), Constant.maxHeight)
        textViewHeightConstraint?.constant = newHeight
    }

    private func updateSendButtonVisibility() {
        sendButton.alpha = textView.text.isEmpty ? 0.0 : 1.0
    }

    @objc private func handleSendButtonTap() {
        guard let text = textView.text, !text.isEmpty else { return }
        delegate?.messagesInputView(self, didTapSend: text)
        clearTextView()
    }

    private func clearTextView() {
        textView.text = ""
        sendButton.alpha = 0.0
        handleTextChange()
    }

    private enum Constant {
        static let bottomInset: CGFloat = 14.0
        static let margin: CGFloat = 14.0
        static let sendButtonSize: CGFloat = 36.0
        static let baseHeight: CGFloat = 36.0
        static let maxHeight: CGFloat = 150.0
        static let textViewCornerRadius: CGFloat = 16.0
        static let textViewFontSize: CGFloat = 16.0
        static let textViewInset: UIEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: sendButtonSize)
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
