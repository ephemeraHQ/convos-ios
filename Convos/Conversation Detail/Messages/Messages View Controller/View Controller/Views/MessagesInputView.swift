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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var _isEditingProfile: Bool = false
    var isEditingProfile: Bool {
        get { _isEditingProfile }
        set { setEditingProfile(newValue, animated: true) }
    }
    private var normalConstraints: [NSLayoutConstraint] = []
    private var editingProfileConstraints: [NSLayoutConstraint] = []

    private var editingViews: [UIView] {
        [editProfileContainer, profileAvatarPickerButton]
    }
    private var normalViews: [UIView] {
        [profileAvatarButton, textView, sendButton, placeholderLabel]
    }

    // MARK: - Base Components

    private lazy var backgroundView: UIView = {
        let view = UIView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        return view
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

    private(set) lazy var contentView: UIView = {
        let view = UIView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        return view
    }()

    private(set) lazy var buttonContainer: UIView = {
        let view = UIView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        return view
    }()

    private(set) lazy var centerContainer: UIView = {
        let view = UIView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        return view
    }()

    private(set) lazy var rightContainer: UIView = {
        let view = UIView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        return view
    }()


    // MARK: - Editing Profile Components

    private(set) lazy var editProfileContainer: UIView = {
        let view = UIView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .colorFillMinimal
        view.layer.cornerRadius = 24.0
        view.layer.masksToBounds = true
        return view
    }()

    private(set) lazy var profileNameTextField: UITextField = {
        let tf = UITextField()
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.font = .systemFont(ofSize: 17.0)
        tf.placeholder = "\(profile.displayName)..."
        tf.returnKeyType = .done
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
        ].forEach { addSubview($0) }

        [
            contentView
        ].forEach { containerView.addSubview($0) }

        [
            buttonContainer,
            centerContainer,
            rightContainer
        ].forEach { contentView.addSubview($0) }

        [
            profileAvatarPickerButton,
            profileAvatarButton,
        ].forEach { buttonContainer.addSubview($0) }

        [
            profileNameTextField,
        ]
        .forEach { editProfileContainer.addSubview($0) }

        [
            editProfileContainer,
            textView,
            placeholderLabel
        ].forEach { centerContainer.addSubview($0) }

        [
            sendButton
        ].forEach { rightContainer.addSubview($0) }
    }

    private func setupConstraints() {
        setupContainerViewHeightConstraint()
        setupLayoutConstraints()
    }

    private func setupContainerViewHeightConstraint() {
        containerViewHeightConstraint = containerView.heightAnchor.constraint(equalToConstant: Constant.baseHeight)
        containerViewHeightConstraint?.isActive = true
    }

    private func setupLayoutConstraints() {
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            containerView.topAnchor.constraint(
                equalTo: topAnchor,
                constant: Constant.margin
            ),
            containerView.leadingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.leadingAnchor,
                constant: Constant.margin
            ),
            containerView.trailingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.trailingAnchor,
                constant: -Constant.margin
            ),

            // containers
            buttonContainer.topAnchor.constraint(
                equalTo: contentView.topAnchor
            ),
            buttonContainer.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor
            ),
            buttonContainer.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor
            ),
            buttonContainer.widthAnchor.constraint(
                equalTo: buttonContainer.heightAnchor
            ),

            centerContainer.topAnchor.constraint(
                equalTo: contentView.topAnchor
            ),
            centerContainer.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor
            ),
            centerContainer.leadingAnchor.constraint(
                equalTo: buttonContainer.trailingAnchor
            ),
            centerContainer.trailingAnchor.constraint(
                equalTo: rightContainer.leadingAnchor
            ),

            rightContainer.topAnchor.constraint(
                equalTo: contentView.topAnchor
            ),
            rightContainer.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor
            ),
            rightContainer.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor
            ),
            rightContainer.widthAnchor.constraint(
                equalTo: rightContainer.heightAnchor
            ),

            // left views
            profileAvatarPickerButton.topAnchor.constraint(
                equalTo: buttonContainer.topAnchor
            ),
            profileAvatarPickerButton.bottomAnchor.constraint(
                equalTo: buttonContainer.bottomAnchor
            ),
            profileAvatarPickerButton.leadingAnchor.constraint(
                equalTo: buttonContainer.leadingAnchor
            ),
            profileAvatarPickerButton.trailingAnchor.constraint(
                equalTo: buttonContainer.trailingAnchor
            ),

            profileAvatarButton.widthAnchor.constraint(
                equalTo: buttonContainer.widthAnchor
            ),
            profileAvatarButton.heightAnchor.constraint(
                equalTo: profileAvatarButton.widthAnchor
            ),
            profileAvatarButton.leadingAnchor.constraint(
                equalTo: buttonContainer.leadingAnchor
            ),
            profileAvatarButton.bottomAnchor.constraint(
                equalTo: buttonContainer.bottomAnchor
            ),

            // center views
            textView.topAnchor.constraint(
                equalTo: centerContainer.topAnchor
            ),
            textView.bottomAnchor.constraint(
                equalTo: centerContainer.bottomAnchor
            ),
            textView.leadingAnchor.constraint(
                equalTo: centerContainer.leadingAnchor
            ),
            textView.trailingAnchor.constraint(
                equalTo: centerContainer.trailingAnchor
            ),

            editProfileContainer.topAnchor.constraint(
                equalTo: centerContainer.topAnchor
            ),
            editProfileContainer.bottomAnchor.constraint(
                equalTo: centerContainer.bottomAnchor
            ),
            editProfileContainer.leadingAnchor.constraint(
                equalTo: centerContainer.leadingAnchor,
                constant: DesignConstants.Spacing.step2x
            ),
            editProfileContainer.trailingAnchor.constraint(
                equalTo: centerContainer.trailingAnchor
            ),

            profileNameTextField.topAnchor.constraint(
                equalTo: editProfileContainer.topAnchor
            ),
            profileNameTextField.bottomAnchor.constraint(
                equalTo: editProfileContainer.bottomAnchor
            ),
            profileNameTextField.leadingAnchor.constraint(
                equalTo: editProfileContainer.leadingAnchor,
                constant: DesignConstants.Spacing.step6x
            ),
            profileNameTextField.trailingAnchor.constraint(
                equalTo: editProfileContainer.trailingAnchor,
                constant: -DesignConstants.Spacing.step6x
            ),

            placeholderLabel.leadingAnchor.constraint(
                equalTo: textView.leadingAnchor,
                constant: Constant.textViewInset.left + 6.0
            ),
            placeholderLabel.centerYAnchor.constraint(
                equalTo: textView.centerYAnchor
            ),
            placeholderLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: textView.trailingAnchor,
                constant: -Constant.textViewInset.right
            ),

            // right views
            sendButton.bottomAnchor.constraint(
                equalTo: rightContainer.bottomAnchor
            ),
            sendButton.trailingAnchor.constraint(
                equalTo: rightContainer.trailingAnchor
            ),
            sendButton.widthAnchor.constraint(
                equalToConstant: Constant.sendButtonSize
            ),
            sendButton.heightAnchor.constraint(
                equalToConstant: Constant.sendButtonSize
            ),
        ])

        normalConstraints = [
            contentView.topAnchor.constraint(
                equalTo: containerView.topAnchor,
                constant: 0.0
            ),
            contentView.bottomAnchor.constraint(
                equalTo: containerView.bottomAnchor,
                constant: 0.0
            ),
            contentView.leadingAnchor.constraint(
                equalTo: containerView.leadingAnchor,
                constant: 0.0
            ),
            contentView.trailingAnchor.constraint(
                equalTo: containerView.trailingAnchor,
                constant: 0.0
            ),
        ]

        editingProfileConstraints = [
            contentView.topAnchor.constraint(
                equalTo: containerView.topAnchor,
                constant: DesignConstants.Spacing.step6x
            ),
            contentView.bottomAnchor.constraint(
                equalTo: containerView.bottomAnchor,
                constant: -DesignConstants.Spacing.step6x
            ),
            contentView.leadingAnchor.constraint(
                equalTo: containerView.leadingAnchor,
                constant: DesignConstants.Spacing.step6x
            ),
            contentView.trailingAnchor.constraint(
                equalTo: containerView.trailingAnchor,
                constant: -DesignConstants.Spacing.step6x
            ),
        ]

        NSLayoutConstraint.activate(normalConstraints)
        updateEditingProfileAlpha()
    }

    private func setEditingProfile(_ editing: Bool, animated: Bool) {
        guard editing != _isEditingProfile else { return }
        _isEditingProfile = editing
        updateForEditingProfile(animated: animated)
    }

    private func updateForEditingProfile(animated: Bool) {
        let toActivate = isEditingProfile ? editingProfileConstraints : normalConstraints
        let toDeactivate = isEditingProfile ? normalConstraints : editingProfileConstraints
        NSLayoutConstraint.deactivate(toDeactivate)
        NSLayoutConstraint.activate(toActivate)
        let animations = {
            self.containerView.cornerRadius = self.isEditingProfile ? 40.0 : 20.0
            self.updateEditingProfileAlpha()
            self.updateContainerViewHeight()
            self.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.3, animations: animations)
        } else {
            animations()
        }
    }

    private func updateEditingProfileAlpha() {
        let editingAlpha: CGFloat = isEditingProfile ? 1 : 0
        let normalAlpha: CGFloat = isEditingProfile ? 0 : 1
        editingViews.forEach { $0.alpha = editingAlpha }
        normalViews.forEach { $0.alpha = normalAlpha }
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
        placeholderLabel.isHidden = !(textView.text?.isEmpty ?? true)
    }

    private func updateContainerViewHeight() {
        if isEditingProfile {
            containerViewHeightConstraint?.constant = 100.0
        } else {
            let size = CGSize(
                width: textView.bounds.width,
                height: .infinity
            )
            let estimatedSize = textView.sizeThatFits(size)
            let newHeight = min(
                max(estimatedSize.height, Constant.baseHeight),
                Constant.maxHeight
            )
            containerViewHeightConstraint?.constant = newHeight
        }
        invalidateIntrinsicContentSize()
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
        isEditingProfile = false
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
