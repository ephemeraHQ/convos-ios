import PhotosUI
import SwiftUI
import UIKit

struct ProfileAvatarButton: View {
    let profile: Profile
    let didTap: () -> Void

    var body: some View {
        Button {
            didTap()
        } label: {
            ProfileAvatarView(profile: profile)
                .padding(8.0)
        }
    }
}

struct ProfileAvatarPickerButton: View {
    let profile: Profile
    @State private var imageSelection: PhotosPickerItem?

    var body: some View {
        PhotosPicker(
            selection: $imageSelection,
            matching: .images,
            photoLibrary: .shared()
        ) {
            Label("Photo Picker", systemImage: "photo.on.rectangle.angled")
                .tint(.colorBackgroundPrimary)
                .labelStyle(.iconOnly)
                .foregroundColor(.white)
                .padding(8.0)
        }
        .background(.colorBackgroundInverted)
        .mask(Circle())
    }
}

struct RandomNameButton: View {
    let onTap: () -> Void
    var body: some View {
        Button {
            onTap()
        } label: {
            Image(systemName: "gear")
                .foregroundColor(.colorTextSecondary)
                .font(.system(size: 16.0))
        }
    }
}

// MARK: - MessagesInputViewDelegate

protocol MessagesInputViewDelegate: AnyObject {
    func messagesInputView(_ view: MessagesInputView, didChangeText text: String)
}

// MARK: - MessagesInputView

final class MessagesInputView: UIView {
    weak var delegate: MessagesInputViewDelegate?
    private var keyboardIsShowing: Bool = false
    private var containerViewHeightConstraint: NSLayoutConstraint?
    private var profile: Profile = .mock()
    private let sendMessage: () -> Void

    private var isEditingProfile: Bool = false

    // MARK: - Editing Profile Components

    private(set) lazy var profileNameTextField: UITextField = {
        let tf = UITextField()
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.font = .systemFont(ofSize: 17.0)
        tf.placeholder = "\(profile.displayName)..."
        return tf
    }()

    private(set) lazy var randomNameButton: SwiftUIViewWrapper<RandomNameButton> = {
        let wrappedView = SwiftUIViewWrapper {
            RandomNameButton {
                //
            }
        }
        wrappedView.translatesAutoresizingMaskIntoConstraints = false
        return wrappedView
    }()

    private(set) lazy var profileAvatarPickerButton: SwiftUIViewWrapper<ProfileAvatarPickerButton> = {
        let wrappedView = SwiftUIViewWrapper {
            ProfileAvatarPickerButton(profile: profile)
        }
        wrappedView.translatesAutoresizingMaskIntoConstraints = false
        return wrappedView
    }()

    // MARK: - Sending Messages Components

    private lazy var backgroundView: UIView = {
        let view = UIView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        return view
    }()

    private(set) lazy var profileAvatarButton: SwiftUIViewWrapper<ProfileAvatarButton> = {
        let wrappedView = SwiftUIViewWrapper {
            ProfileAvatarButton(profile: profile) { [weak self] in
                guard let self = self else { return }
                isEditingProfile = true
            }
        }
        wrappedView.translatesAutoresizingMaskIntoConstraints = false
        return wrappedView
    }()

    private(set) lazy var placeholderLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Chat as \(profile.displayName)"
        label.textColor = .colorTextTertiary
        label.font = .systemFont(ofSize: Constant.textViewFontSize)
        label.isUserInteractionEnabled = false
        return label
    }()

    private(set) lazy var containerView: ShadowedRoundedView = {
        let container = ShadowedRoundedView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .clear
        container.cornerRadius = Constant.textViewCornerRadius
        container.fillColor = .colorBackgroundPrimary
        container.shadowColor = UIColor.black.withAlphaComponent(0.15)
        container.shadowOpacity = 1.0
        container.shadowRadius = 16.0
        container.shadowOffset = CGSize(width: 0.0, height: 4.0)
        return container
    }()

    private(set) lazy var buttonContainer: UIView = {
        let view = UIView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
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
        placeholderLabel.isHidden = !(textView.text?.isEmpty ?? true)
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
        [
            backgroundView,
            containerView,
            buttonContainer,
            profileAvatarPickerButton,
            profileAvatarButton,
            profileNameTextField,
            textView,
            placeholderLabel,
            sendButton
        ].forEach { addSubview($0) }
    }

    private func setupConstraints() {
        setupContainerViewHeightConstraint()
        setupLayoutConstraints()
    }

    private func setupContainerViewHeightConstraint() {
        containerViewHeightConstraint = textView.heightAnchor.constraint(equalToConstant: Constant.baseHeight)
        containerViewHeightConstraint?.isActive = true
    }

    private func setupLayoutConstraints() {
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            containerView.topAnchor.constraint(equalTo: textView.topAnchor),
            containerView.leadingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.leadingAnchor,
                constant: Constant.margin
            ),
            containerView.trailingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.trailingAnchor,
                constant: -Constant.margin
            ),
            containerView.bottomAnchor.constraint(equalTo: textView.bottomAnchor),

            buttonContainer.topAnchor.constraint(equalTo: containerView.topAnchor),
            buttonContainer.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            buttonContainer.leadingAnchor.constraint(
                equalTo: containerView.leadingAnchor
            ),
            buttonContainer.widthAnchor.constraint(equalTo: buttonContainer.heightAnchor),

            profileAvatarButton.heightAnchor.constraint(equalToConstant: Constant.baseHeight),
            profileAvatarButton.widthAnchor.constraint(equalTo: profileAvatarButton.heightAnchor),
            profileAvatarButton.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor),
            profileAvatarButton.bottomAnchor.constraint(equalTo: buttonContainer.bottomAnchor),

            profileAvatarPickerButton.topAnchor.constraint(equalTo: buttonContainer.topAnchor),
            profileAvatarPickerButton.bottomAnchor.constraint(equalTo: buttonContainer.bottomAnchor),
            profileAvatarPickerButton.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor),
            profileAvatarPickerButton.trailingAnchor.constraint(equalTo: buttonContainer.trailingAnchor),

            textView.topAnchor.constraint(equalTo: topAnchor, constant: Constant.margin),
            textView.leadingAnchor.constraint(equalTo: profileAvatarButton.trailingAnchor),
            textView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            profileNameTextField.topAnchor.constraint(equalTo: textView.topAnchor),
            profileNameTextField.bottomAnchor.constraint(equalTo: textView.bottomAnchor),
            profileNameTextField.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            profileNameTextField.trailingAnchor.constraint(equalTo: textView.trailingAnchor),

            sendButton.bottomAnchor.constraint(equalTo: textView.bottomAnchor),
            sendButton.trailingAnchor.constraint(equalTo: textView.trailingAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: Constant.sendButtonSize),
            sendButton.heightAnchor.constraint(equalToConstant: Constant.sendButtonSize),

            placeholderLabel.leadingAnchor
                .constraint(equalTo: textView.leadingAnchor, constant: Constant.textViewInset.left + 6.0),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 8),
            placeholderLabel.trailingAnchor
                .constraint(lessThanOrEqualTo: textView.trailingAnchor, constant: -Constant.textViewInset.right),
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

    override var intrinsicContentSize: CGSize {
        let textHeight = (containerViewHeightConstraint?.constant ?? Constant.baseHeight) + (Constant.margin * 2.0)
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
        updateContainerViewHeight()
        invalidateIntrinsicContentSize()
        placeholderLabel.isHidden = !(textView.text?.isEmpty ?? true)
    }

    private func updateContainerViewHeight() {
        let size = CGSize(width: textView.bounds.width, height: .infinity)
        let estimatedSize = textView.sizeThatFits(size)
        let newHeight = min(max(estimatedSize.height, Constant.baseHeight), Constant.maxHeight)
        containerViewHeightConstraint?.constant = newHeight
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
        placeholderLabel.isHidden = false
    }

    enum Constant {
        static let bottomInset: CGFloat = 14.0
        static let margin: CGFloat = 14.0
        static let sendButtonSize: CGFloat = 36.0
        static let baseHeight: CGFloat = 36.0
        static let maxHeight: CGFloat = 150.0
        static let textViewCornerRadius: CGFloat = 16.0
        static let textViewFontSize: CGFloat = 16.0
        static let textViewInset: UIEdgeInsets = UIEdgeInsets(top: 8.0,
                                                              left: 0.0,
                                                              bottom: 8.0,
                                                              right: sendButtonSize)
    }
}

// MARK: - ShadowedRoundedView

class ShadowedRoundedView: UIView {
    private var shadowLayer: CAShapeLayer?
    var cornerRadius: CGFloat = 20.0 { didSet { setNeedsLayout() } }
    var fillColor: UIColor = .colorBackgroundPrimary { didSet { setNeedsLayout() } }
    var shadowColor: UIColor = UIColor.black.withAlphaComponent(0.15) { didSet { setNeedsLayout() } }
    var shadowOpacity: Float = 1.0 { didSet { setNeedsLayout() } }
    var shadowRadius: CGFloat = 16.0 { didSet { setNeedsLayout() } }
    var shadowOffset: CGSize = CGSize(width: 0, height: 4) { didSet { setNeedsLayout() } }

    override func layoutSubviews() {
        super.layoutSubviews()
        shadowLayer?.removeFromSuperlayer()
        let layer = CAShapeLayer()
        layer.path = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).cgPath
        layer.fillColor = fillColor.cgColor
        layer.shadowColor = shadowColor.cgColor
        layer.shadowPath = layer.path
        layer.shadowOffset = shadowOffset
        layer.shadowOpacity = shadowOpacity
        layer.shadowRadius = shadowRadius
        self.layer.insertSublayer(layer, at: 0)
        shadowLayer = layer
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
        placeholderLabel.isHidden = !textView.text.isEmpty
    }
}

#if DEBUG
import SwiftUI
import UIKit

struct MessagesInputView_Previews: PreviewProvider {
    struct Wrapper: UIViewRepresentable {
        func makeUIView(context: Context) -> MessagesInputView {
            let view = MessagesInputView(sendMessage: { print("Send tapped") })
            view.sendButtonEnabled = true
            return view
        }
        func updateUIView(_ uiView: MessagesInputView, context: Context) {}
    }
    static var previews: some View {
        Wrapper()
            .frame(height: 80)
            .previewLayout(.sizeThatFits)
            .padding()
    }
}

#endif
