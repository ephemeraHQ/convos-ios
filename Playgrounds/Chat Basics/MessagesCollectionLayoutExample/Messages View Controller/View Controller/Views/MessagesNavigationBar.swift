import UIKit

class MessagesNavigationBar: UIView {
    enum Constants {
        static let height: CGFloat = 44.0
        static let horizontalPadding: CGFloat = 16.0
        static let backButtonSize: CGFloat = 32.0
    }

    // MARK: - Properties

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public Methods

    func configure(title: String, backButtonIcon: UIImage? = UIImage(systemName: "chevron.left"), backButtonAction: @escaping () -> Void) {
        titleLabel.text = title
        backButton.setImage(backButtonIcon, for: .normal)
        backButton.addAction(UIAction { _ in backButtonAction() }, for: .touchUpInside)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        backgroundColor = .clear

        // Update blur view frame
        blurView.frame = bounds

        // Update back button frame
        backButton.frame = CGRect(
            x: Constants.horizontalPadding,
            y: safeAreaInsets.top,
            width: Constants.backButtonSize,
            height: Constants.height
        )

        // Update title label frame
        let titleLabelXPadding: CGFloat = Constants.backButtonSize + (Constants.horizontalPadding * 2)
        titleLabel.frame = CGRect(
            x: titleLabelXPadding,
            y: safeAreaInsets.top,
            width: bounds.width - (titleLabelXPadding * 2),
            height: Constants.height
        )
    }

    // MARK: - Private Methods
    
    private func setupUI() {
        // Setup blur view
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(blurView)

        // Setup title label
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.textColor = .label
        addSubview(titleLabel)

        // Setup back button
        backButton.tintColor = .label
        addSubview(backButton)
    }
}
