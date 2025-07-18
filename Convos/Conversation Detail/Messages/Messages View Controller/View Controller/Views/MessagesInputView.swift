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

struct ProfileSettingsButton: View {
    let onTap: () -> Void
    var body: some View {
        Button {
            onTap()
        } label: {
            Image(systemName: "gear")
                .foregroundStyle(.colorTextSecondary)
                .font(.system(size: 24.0))
                .padding(8.0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.colorFillMinimal)
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
    private var profile: Profile = .mock() {
        didSet {
            profileAvatarButton.update(
                profileAvatarButton(for: profile)
            )
            placeholderLabel.text = "Chat as \(profile.displayName)"
        }
    }
    private let sendMessage: () -> Void

    private var _isEditingProfile: Bool = false
    var isEditingProfile: Bool {
        get { _isEditingProfile }
        set { setEditingProfile(newValue, animated: true) }
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
        container.backgroundColor = .clear
        container.cornerRadius = Constant.textViewCornerRadius
        container.fillColor = .colorBackgroundPrimary
        container.shadowColor = UIColor.black.withAlphaComponent(0.15)
        container.shadowOpacity = 1.0
        container.shadowRadius = 16.0
        container.shadowOffset = CGSize(width: 0.0, height: 4.0)
        return container
    }()

    private(set) lazy var leftContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }()

    private(set) lazy var centerContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }()

    private(set) lazy var rightContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }()

    // MARK: - Editing Profile Components

    private(set) lazy var editProfileContainer: UIView = {
        let view = UIView(frame: .zero)
        view.backgroundColor = .colorFillMinimal
        view.layer.cornerRadius = 24.0
        view.layer.masksToBounds = true
        return view
    }()

    private(set) lazy var profileNameTextField: UITextField = {
        let tf = UITextField()
        tf.font = .systemFont(ofSize: 17.0)
        tf.placeholder = "Somebody..."
        tf.delegate = self
        tf.clearButtonMode = .whileEditing
        tf.returnKeyType = .done
        return tf
    }()

    private(set) lazy var randomNameButton: SwiftUIViewWrapper<RandomNameButton> = {
        let wrappedView = SwiftUIViewWrapper {
            RandomNameButton {
                //
            }
        }
        return wrappedView
    }()

    private(set) lazy var profileAvatarPickerButton: SwiftUIViewWrapper<ProfileAvatarPickerButton> = {
        let wrappedView = SwiftUIViewWrapper {
            ProfileAvatarPickerButton(profile: profile)
        }
        return wrappedView
    }()

    private(set) lazy var profileSettingsButton: SwiftUIViewWrapper<ProfileSettingsButton> = {
        let wrappedView = SwiftUIViewWrapper {
            ProfileSettingsButton {
                //
            }
        }
        return wrappedView
    }()

    // MARK: - Sending Messages Components

    private func profileAvatarButton(for profile: Profile) -> ProfileAvatarButton {
        ProfileAvatarButton(profile: profile) { [weak self] in
            guard let self = self else { return }
            isEditingProfile = true
        }
    }

    private(set) lazy var profileAvatarButton: SwiftUIViewWrapper<ProfileAvatarButton> = {
        let wrappedView = SwiftUIViewWrapper {
            profileAvatarButton(for: profile)
        }
        return wrappedView
    }()

    private(set) lazy var placeholderLabel: UILabel = {
        let label = UILabel()
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
        tv.isScrollEnabled = false
        tv.delegate = self
        return tv
    }()

    lazy var sendButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        button.tintColor = .colorBackgroundInverted
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
    }

    private func configureBackground() {
        backgroundColor = .clear
    }

    private func addSubviews() {
        addSubview(backgroundView)
        addSubview(containerView)
        containerView.addSubview(leftContainer)
        containerView.addSubview(centerContainer)
        containerView.addSubview(rightContainer)

        [profileAvatarPickerButton, profileAvatarButton].forEach { leftContainer.addSubview($0) }
        [profileNameTextField].forEach { editProfileContainer.addSubview($0) }
        [editProfileContainer, textView, placeholderLabel].forEach { centerContainer.addSubview($0) }
        [sendButton, profileSettingsButton].forEach { rightContainer.addSubview($0) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Layout backgroundView to fill self
        backgroundView.frame = bounds

        // Calculate containerView frame
        let margin = Constant.margin
        let containerWidth = bounds.width - margin * 2.0
        let containerHeight: CGFloat
        if isEditingProfile {
            containerHeight = 100.0
        } else {
            let size = CGSize(width: containerWidth, height: .infinity)
            let estimatedSize = textView.sizeThatFits(size)
            containerHeight = min(max(estimatedSize.height, Constant.baseHeight), Constant.maxHeight)
        }
        let containerY = margin
        containerView.frame = CGRect(x: margin, y: containerY, width: containerWidth, height: containerHeight)
        containerView.cornerRadius = isEditingProfile ? 40.0 : Constant.textViewCornerRadius

        // Calculate container insets based on editing state
        let containerInset: CGFloat = isEditingProfile ? DesignConstants.Spacing.step6x : 0.0
        let containerBounds = containerView.bounds.insetBy(dx: containerInset, dy: containerInset)

        // Layout containers within containerView
        // Use outer containerWidth and containerHeight
        let leftWidth = min(Constant.avatarSize, containerHeight - 2 * containerInset)
        let rightWidth = min(Constant.sendButtonSize, containerHeight - 2 * containerInset)
        let centerWidth = containerWidth - 2 * containerInset - leftWidth - rightWidth

        leftContainer.frame = CGRect(x: containerBounds.minX, y: containerBounds.minY, width: leftWidth, height: containerBounds.height)
        centerContainer.frame = CGRect(x: containerBounds.minX + leftWidth, y: containerBounds.minY, width: centerWidth, height: containerBounds.height)
        rightContainer.frame = CGRect(x: containerBounds.minX + leftWidth + centerWidth, y: containerBounds.minY, width: rightWidth, height: containerBounds.height)

        // Layout subviews within containers using frame-based layout
        layoutLeftContainerSubviews()
        layoutCenterContainerSubviews()
        layoutRightContainerSubviews()
    }

    private func layoutLeftContainerSubviews() {
        let containerBounds = leftContainer.bounds

        // Profile avatar picker button fills the container
        profileAvatarPickerButton.frame = containerBounds

        // Profile avatar button is centered with fixed size
        let avatarSize = min(Constant.avatarSize, containerBounds.width, containerBounds.height)
        let avatarX = (containerBounds.width - avatarSize) / 2
        let avatarY = (containerBounds.height - avatarSize) / 2
        profileAvatarButton.frame = CGRect(x: avatarX, y: avatarY, width: avatarSize, height: avatarSize)
    }

    private func layoutCenterContainerSubviews() {
        let containerBounds = centerContainer.bounds

        // Text view fills the container
        textView.frame = containerBounds

        // Edit profile container fills the container with margins
        let margin = DesignConstants.Spacing.step2x
        editProfileContainer.frame = containerBounds.insetBy(dx: margin, dy: 0)

        // Profile name text field fills the edit profile container with margins
        let textFieldMargin = DesignConstants.Spacing.step6x
        profileNameTextField.frame = editProfileContainer.bounds.insetBy(dx: textFieldMargin, dy: 0)

        // Placeholder label positioned within text view
        let placeholderX = Constant.textViewInset.left + 6.0
        let placeholderY = (containerBounds.height - placeholderLabel.intrinsicContentSize.height) / 2
        let placeholderWidth = containerBounds.width - placeholderX - Constant.textViewInset.right
        placeholderLabel.frame = CGRect(x: placeholderX, y: placeholderY, width: placeholderWidth, height: placeholderLabel.intrinsicContentSize.height)
    }

    private func layoutRightContainerSubviews() {
        let containerBounds = rightContainer.bounds

        // Send button is centered with fixed size
        let sendButtonSize = min(Constant.sendButtonSize, containerBounds.width, containerBounds.height)
        let sendButtonX = (containerBounds.width - sendButtonSize) / 2
        let sendButtonY = (containerBounds.height - sendButtonSize) / 2
        sendButton.frame = CGRect(x: sendButtonX, y: sendButtonY, width: sendButtonSize, height: sendButtonSize)

        // Profile settings button fills the container
        profileSettingsButton.frame = containerBounds
    }

    // Remove setupConstraints, setupContainerViewHeightConstraint, setupLayoutConstraints, normalConstraints, editingProfileConstraints, and related logic.
    // Update updateForEditingProfile(animated:) to animate frame and cornerRadius changes.
    private func setEditingProfile(_ editing: Bool, animated: Bool) {
        guard editing != _isEditingProfile else { return }
        _isEditingProfile = editing
        if isEditingProfile {
            profileNameTextField.becomeFirstResponder()
        }
        updateForEditingProfile(animated: animated)
    }

    private func updateForEditingProfile(animated: Bool) {
        let animations = {
            self.setNeedsLayout()
            self.layoutIfNeeded()
            self.updateEditingProfileAlpha()
        }
        if animated {
            UIView.animate(withDuration: 0.3, delay: 0.0, options: [.layoutSubviews], animations: animations)
        } else {
            animations()
        }
    }

    private func updateEditingProfileAlpha() {
        let editingAlpha: CGFloat = isEditingProfile ? 1 : 0
        let normalAlpha: CGFloat = isEditingProfile ? 0 : 1
        [editProfileContainer, profileAvatarPickerButton, profileSettingsButton].forEach { $0.alpha = editingAlpha }
        [profileAvatarButton, textView, sendButton, placeholderLabel].forEach { $0.alpha = normalAlpha }
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
        let margin = Constant.margin
        let containerWidth = bounds.width - margin * 2.0
        let containerHeight: CGFloat
        if isEditingProfile {
            containerHeight = 100.0
        } else {
            let size = CGSize(width: containerWidth, height: .infinity)
            let estimatedSize = textView.sizeThatFits(size)
            containerHeight = min(max(estimatedSize.height, Constant.baseHeight), Constant.maxHeight)
        }
        let textHeight = containerHeight + (margin * 2.0)
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
        placeholderLabel.isHidden = !(textView.text?.isEmpty ?? true)
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
        static let avatarSize: CGFloat = 36.0
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

// MARK: - UITextFieldDelegate

extension MessagesInputView: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textView.becomeFirstResponder()
        if let name = textField.text, !name.isEmpty {
            profile = .mock(name: name)
        } else {
            profile = .mock()
        }
        isEditingProfile = false
        return true
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

fileprivate struct Wrapper: UIViewRepresentable {
    @Binding var isEditing: Bool
    func makeUIView(context: Context) -> MessagesInputView {
        let view = MessagesInputView(sendMessage: { print("Send tapped") })
        view.sendButtonEnabled = true
        return view
    }
    func updateUIView(_ uiView: MessagesInputView, context: Context) {
        uiView.isEditingProfile = isEditing
    }
}

#Preview {
    @Previewable @State var isEditing: Bool = false

    VStack(spacing: 20.0) {
        Wrapper(isEditing: $isEditing)
            .frame(height: 80)
            .padding()

        Button {
            isEditing.toggle()
        } label: {
            Text("Toggle Editing")
        }
    }
}

#endif
